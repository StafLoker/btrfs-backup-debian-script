#!/bin/bash

# BTRFS Backup Main Script
# This script performs comprehensive system backups using BTRFS snapshots

set -euo pipefail

# Color definitions for output
readonly RED='\033[31m'
readonly YELLOW='\033[33m'
readonly GREEN='\033[32m'
readonly BLUE='\033[34m'
readonly RESET='\033[0m'

# Configuration files
readonly ENV_FILE="/etc/btrfs-backup/.env"
readonly CONFIG_FILE="/etc/btrfs-backup/config.yaml"
readonly SCRIPT_NAME="btrfs-backup"
readonly HOSTNAME=$(hostname)
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)
readonly TEMP_DIR="/tmp/backup_${HOSTNAME}_${TIMESTAMP}"

# Global variables
NOTIFICATIONS_ENABLED=false
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
MOUNTED_DISKS=()
BACKUP_SUCCESS=true
ERROR_MESSAGES=()

# Load environment variables if they exist
load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
        if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
            NOTIFICATIONS_ENABLED=true
        fi
    fi
}

# Check if config file exists
check_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "ERROR" "Configuration file $CONFIG_FILE not found"
        exit 1
    fi
}

# Function to log messages
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        DEBUG) 
            syslog_level="debug"
            color="$BLUE"
            ;;
        INFO) 
            syslog_level="info"
            color="$GREEN"
            ;;
        WARNING) 
            syslog_level="warning"
            color="$YELLOW"
            ;;
        ERROR) 
            syslog_level="err"
            color="$RED"
            ERROR_MESSAGES+=("$message")
            BACKUP_SUCCESS=false
            ;;
        *) 
            syslog_level="notice"
            color="$RESET"
            ;;
    esac
    
    # Log to syslog
    logger -p user.$syslog_level -t "$SCRIPT_NAME" "$message"
    
    # Log to stdout with color
    echo -e "${color}[$level] $timestamp - $message${RESET}"
}

# Function to send Telegram notifications
send_telegram_notification() {
    if [[ "$NOTIFICATIONS_ENABLED" == "true" ]]; then
        local message="$1"
        local api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
        
        curl -s -X POST "$api_url" \
            -d chat_id="$TELEGRAM_CHAT_ID" \
            -d text="$message" \
            -d parse_mode="Markdown" > /dev/null || {
            log "WARNING" "Failed to send Telegram notification"
        }
    fi
}

# Function to handle errors and send notifications
handle_error() {
    local error_msg="$1"
    log "ERROR" "$error_msg"
    
    if [[ "$NOTIFICATIONS_ENABLED" == "true" ]]; then
        send_telegram_notification "🚨 *Backup Error on $HOSTNAME*%0A%0AError: $error_msg%0ATime: $(date)"
    fi
}

# Function to mount backup partitions
mount_backup_partitions() {
    log "INFO" "Mounting backup partitions..."
    
    local parts_count=$(yq eval '.parts | length' "$CONFIG_FILE")
    
    for ((i=0; i<parts_count; i++)); do
        local label=$(yq eval ".parts[$i].label" "$CONFIG_FILE")
        local path=$(yq eval ".parts[$i].path" "$CONFIG_FILE")
        local dev=$(yq eval ".parts[$i].dev" "$CONFIG_FILE")
        
        log "INFO" "Mounting $label: $dev -> $path"
        
        # Create mount point if it doesn't exist
        mkdir -p "$path"
        
        # Check if already mounted
        if mountpoint -q "$path"; then
            log "INFO" "$label already mounted at $path"
        else
            if mount "$dev" "$path"; then
                log "INFO" "Successfully mounted $label"
                MOUNTED_DISKS+=("$path")
            else
                handle_error "Failed to mount $dev to $path"
                return 1
            fi
        fi
    done
    
    return 0
}

# Function to verify and create directory structure
verify_directory_structure() {
    log "INFO" "Verifying directory structure on backup disks..."
    
    local parts_count=$(yq eval '.parts | length' "$CONFIG_FILE")
    
    for ((i=0; i<parts_count; i++)); do
        local label=$(yq eval ".parts[$i].label" "$CONFIG_FILE")
        local path=$(yq eval ".parts[$i].path" "$CONFIG_FILE")
        
        local host_dir="${path}/${HOSTNAME}"
        local data_dir="${host_dir}/data"
        local snapshots_dir="${host_dir}/snapshots"
        
        log "INFO" "Verifying structure for $label"
        
        # Create host directory
        mkdir -p "$host_dir"
        
        # Create data subvolume if it doesn't exist
        if [[ ! -d "$data_dir" ]]; then
            log "INFO" "Creating data subvolume: $data_dir"
            if ! btrfs subvolume create "$data_dir"; then
                handle_error "Failed to create data subvolume for $label"
                continue
            fi
        fi
        
        # Create snapshots directories
        mkdir -p "$snapshots_dir"/{daily,weekly,monthly}
        
        log "INFO" "Directory structure verified for $label"
    done
}

# Function to backup PostgreSQL databases
backup_postgresql() {
    local pg_global=$(yq eval '.backups.postgresql.global // false' "$CONFIG_FILE")
    local pg_all_db=$(yq eval '.backups.postgresql.all_db // false' "$CONFIG_FILE")
    
    if [[ "$pg_global" == "true" ]] || [[ "$pg_all_db" == "true" ]]; then
        log "INFO" "Starting PostgreSQL backup..."
        
        if ! command -v pg_dumpall &>/dev/null; then
            log "WARNING" "pg_dumpall not found, skipping PostgreSQL backup"
            return
        fi
        
        # Create temp directory for PostgreSQL backups
        local pg_temp_dir="$TEMP_DIR/postgresql"
        mkdir -p "$pg_temp_dir"
        
        # Backup global configurations if enabled
        if [[ "$pg_global" == "true" ]]; then
            log "INFO" "Backing up PostgreSQL global configurations..."
            if sudo -u postgres pg_dumpall --globals-only > "$pg_temp_dir/globals_${TIMESTAMP}.sql"; then
                log "INFO" "PostgreSQL globals backup completed"
            else
                handle_error "Failed to backup PostgreSQL globals"
            fi
        fi
        
        # Backup all databases if enabled
        if [[ "$pg_all_db" == "true" ]]; then
            log "INFO" "Backing up all PostgreSQL databases..."
            local databases
            if databases=$(sudo -u postgres psql -t -c "SELECT datname FROM pg_database WHERE datistemplate = false;"); then
                while IFS= read -r db; do
                    db=$(echo "$db" | xargs) # Trim whitespace
                    if [[ -n "$db" ]]; then
                        log "INFO" "Backing up database: $db"
                        if sudo -u postgres pg_dump "$db" > "$pg_temp_dir/${db}_${TIMESTAMP}.sql"; then
                            log "INFO" "Database $db backup completed"
                        else
                            handle_error "Failed to backup database $db"
                        fi
                    fi
                done <<< "$databases"
            else
                handle_error "Failed to get database list"
            fi
        fi
        
        # Copy PostgreSQL backups to each backup disk
        copy_to_backup_disks "$pg_temp_dir" "postgresql"
        
        log "INFO" "PostgreSQL backup completed"
    else
        log "INFO" "PostgreSQL backup disabled"
    fi
}

# Function to backup /etc directory
backup_etc() {
    local etc_enabled=$(yq eval '.backups.etc' "$CONFIG_FILE")
    
    if [[ "$etc_enabled" == "true" ]]; then
        log "INFO" "Starting /etc backup..."
        
        local etc_temp_dir="$TEMP_DIR/etc"
        mkdir -p "$etc_temp_dir"
        
        # Create exclusion list for sensitive files
        local exclude_file="$TEMP_DIR/etc_exclude.txt"
        cat > "$exclude_file" <<EOF
/etc/shadow
/etc/shadow-
/etc/gshadow
/etc/gshadow-
/etc/ssh/ssh_host_*
/etc/ssl/private/*
/etc/letsencrypt/live/*/privkey.pem
/etc/letsencrypt/archive/*/privkey*.pem
EOF

        # Backup /etc excluding sensitive files
        if rsync -av --exclude-from="$exclude_file" /etc/ "$etc_temp_dir/"; then
            log "INFO" "/etc backup completed"
            copy_to_backup_disks "$etc_temp_dir" "etc"
        else
            handle_error "Failed to backup /etc directory"
        fi
        
        log "INFO" "/etc backup completed"
    else
        log "INFO" "/etc backup disabled"
    fi
}

# Function to backup services
backup_services() {
    log "INFO" "Starting services backup..."
    
    local services_count=$(yq eval '.backups.services | length' "$CONFIG_FILE")
    
    if [[ $services_count -eq 0 ]]; then
        log "INFO" "No services configured for backup"
        return
    fi
    
    local stopped_services=()
    
    # Stop all services first
    for ((i=0; i<services_count; i++)); do
        local service_label=$(yq eval ".backups.services[$i].label" "$CONFIG_FILE")
        local systemd_service=$(yq eval ".backups.services[$i].systemd" "$CONFIG_FILE")
        
        if [[ -n "$systemd_service" ]] && [[ "$systemd_service" != "null" ]]; then
            log "INFO" "Stopping service: $systemd_service"
            if systemctl stop "$systemd_service"; then
                stopped_services+=("$systemd_service")
                log "INFO" "Service $systemd_service stopped"
            else
                log "WARNING" "Failed to stop service $systemd_service"
            fi
        fi
    done
    
    # Backup each service
    for ((i=0; i<services_count; i++)); do
        local service_label=$(yq eval ".backups.services[$i].label" "$CONFIG_FILE")
        local docker_compose=$(yq eval ".backups.services[$i].docker_compsose // \"\"" "$CONFIG_FILE")
        local config_path=$(yq eval ".backups.services[$i].config // \"\"" "$CONFIG_FILE")
        local data_files=$(yq eval ".backups.services[$i].data.files // \"\"" "$CONFIG_FILE")
        local data_pg_db=$(yq eval ".backups.services[$i].data.pg-db // \"\"" "$CONFIG_FILE")
        local logs_path=$(yq eval ".backups.services[$i].logs // \"\"" "$CONFIG_FILE")
        
        log "INFO" "Backing up service: $service_label"
        
        local service_temp_dir="$TEMP_DIR/services/$service_label"
        mkdir -p "$service_temp_dir"
        
        # Backup Docker Compose if specified
        if [[ -n "$docker_compose" ]] && [[ "$docker_compose" != "null" ]] && [[ -d "$docker_compose" ]]; then
            log "INFO" "Backing up Docker Compose for $service_label: $docker_compose"
            local compose_backup_dir="$service_temp_dir/docker_compose"
            mkdir -p "$compose_backup_dir"
            
            # Copy docker-compose files
            find "$docker_compose" -maxdepth 1 \( -name "docker-compose.yml" -o -name "docker-compose.yaml" \) -exec cp {} "$compose_backup_dir/" \; 2>/dev/null
            
            # Copy .env files
            find "$docker_compose" -maxdepth 1 -name ".env*" -exec cp {} "$compose_backup_dir/" \; 2>/dev/null
            
            # Copy additional config files
            for config_file in "Dockerfile" ".dockerignore" "docker-compose.override.yml" "docker-compose.override.yaml"; do
                if [[ -f "$docker_compose/$config_file" ]]; then
                    cp "$docker_compose/$config_file" "$compose_backup_dir/" 2>/dev/null
                fi
            done
            
            log "INFO" "Docker Compose backup completed for $service_label"
        fi
        
        # Backup configuration if specified and not excluded by /etc backup
        if [[ -n "$config_path" ]] && [[ "$config_path" != "null" ]] && [[ -d "$config_path" ]]; then
            local etc_enabled=$(yq eval '.backups.etc // false' "$CONFIG_FILE")
            
            # Skip if /etc backup is enabled and config path starts with /etc/
            if [[ "$etc_enabled" == "true" ]] && [[ "$config_path" =~ ^/etc/ ]]; then
                log "INFO" "Skipping config backup for $service_label (covered by /etc backup): $config_path"
            else
                log "INFO" "Backing up configuration for $service_label: $config_path"
                local config_backup_dir="$service_temp_dir/config"
                mkdir -p "$config_backup_dir"
                
                if rsync -av "$config_path/" "$config_backup_dir/"; then
                    log "INFO" "Configuration backup completed for $service_label"
                else
                    handle_error "Failed to backup configuration for $service_label: $config_path"
                fi
            fi
        fi
        
        # Backup data files if specified
        if [[ -n "$data_files" ]] && [[ "$data_files" != "null" ]] && [[ -d "$data_files" ]]; then
            log "INFO" "Backing up data files for $service_label: $data_files"
            local data_backup_dir="$service_temp_dir/data_files"
            mkdir -p "$data_backup_dir"
            
            if rsync -av "$data_files/" "$data_backup_dir/"; then
                log "INFO" "Data files backup completed for $service_label"
            else
                handle_error "Failed to backup data files for $service_label: $data_files"
            fi
        fi
        
        # Backup PostgreSQL database if specified
        if [[ -n "$data_pg_db" ]] && [[ "$data_pg_db" != "null" ]]; then
            log "INFO" "Backing up PostgreSQL database for $service_label: $data_pg_db"
            local db_backup_dir="$service_temp_dir/database"
            mkdir -p "$db_backup_dir"
            
            if command -v pg_dump &>/dev/null; then
                if sudo -u postgres pg_dump "$data_pg_db" > "$db_backup_dir/${data_pg_db}_${TIMESTAMP}.sql"; then
                    log "INFO" "PostgreSQL database backup completed for $service_label: $data_pg_db"
                else
                    handle_error "Failed to backup PostgreSQL database for $service_label: $data_pg_db"
                fi
            else
                log "WARNING" "pg_dump not found, skipping database backup for $service_label"
            fi
        fi
        
        # Backup logs if specified
        if [[ -n "$logs_path" ]] && [[ "$logs_path" != "null" ]] && [[ -d "$logs_path" ]]; then
            log "INFO" "Backing up logs for $service_label: $logs_path"
            local logs_backup_dir="$service_temp_dir/logs"
            mkdir -p "$logs_backup_dir"
            
            if rsync -av "$logs_path/" "$logs_backup_dir/"; then
                log "INFO" "Logs backup completed for $service_label"
            else
                handle_error "Failed to backup logs for $service_label: $logs_path"
            fi
        fi
        
        # Copy service backup to all backup disks
        copy_to_backup_disks "$service_temp_dir" "services/$service_label"
        
        log "INFO" "Service backup completed: $service_label"
    done
    
    # Restart all stopped services
    for service in "${stopped_services[@]}"; do
        log "INFO" "Starting service: $service"
        if systemctl start "$service"; then
            log "INFO" "Service $service started"
        else
            handle_error "Failed to start service $service"
        fi
    done
    
    log "INFO" "Services backup completed"
}

# Function to backup certificates
backup_certificates() {
    local certs_enabled=$(yq eval '.backups.certificates' "$CONFIG_FILE")
    
    if [[ "$certs_enabled" == "true" ]]; then
        log "INFO" "Starting certificates backup..."
        
        local certs_temp_dir="$TEMP_DIR/certificates"
        mkdir -p "$certs_temp_dir"
        
        # Backup Let's Encrypt certificates
        if [[ -d "/etc/letsencrypt" ]]; then
            log "INFO" "Backing up Let's Encrypt certificates"
            rsync -av /etc/letsencrypt/ "$certs_temp_dir/letsencrypt/" || {
                handle_error "Failed to backup Let's Encrypt certificates"
            }
        fi
        
        # Backup SSL private keys (with proper permissions)
        if [[ -d "/etc/ssl/private" ]]; then
            log "INFO" "Backing up SSL private keys"
            rsync -av /etc/ssl/private/ "$certs_temp_dir/ssl_private/" || {
                handle_error "Failed to backup SSL private keys"
            }
        fi
        
        # Backup Nginx SSL certificates if they exist
        if [[ -d "/etc/nginx/ssl" ]]; then
            log "INFO" "Backing up Nginx SSL certificates"
            rsync -av /etc/nginx/ssl/ "$certs_temp_dir/nginx_ssl/" || {
                handle_error "Failed to backup Nginx SSL certificates"
            }
        fi
        
        copy_to_backup_disks "$certs_temp_dir" "certificates"
        
        log "INFO" "Certificates backup completed"
    else
        log "INFO" "Certificates backup disabled"
    fi
}

# Function to backup configured paths
backup_configured_paths() {
    log "INFO" "Starting configured paths backup..."
    
    local paths_count=$(yq eval '.backups.paths | length' "$CONFIG_FILE")
    
    if [[ $paths_count -eq 0 ]]; then
        log "INFO" "No paths configured for backup"
        return
    fi
    
    # Backup each configured path
    for ((i=0; i<paths_count; i++)); do
        local backup_path=$(yq eval ".backups.paths[$i].path" "$CONFIG_FILE")
        local label=$(yq eval ".backups.paths[$i].label" "$CONFIG_FILE")
        
        if [[ -d "$backup_path" ]]; then
            log "INFO" "Backing up path: $backup_path (label: $label)"
            
            local path_temp_dir="$TEMP_DIR/paths/$label"
            mkdir -p "$path_temp_dir"
            
            if rsync -av "$backup_path/" "$path_temp_dir/"; then
                log "INFO" "Path $backup_path backup completed"
                copy_to_backup_disks "$path_temp_dir" "paths/$label"
            else
                handle_error "Failed to backup path $backup_path"
            fi
        else
            log "WARNING" "Path $backup_path does not exist, skipping"
        fi
    done
    
    log "INFO" "Configured paths backup completed"
}

# Function to copy data to backup disks
copy_to_backup_disks() {
    local source_dir="$1"
    local dest_subdir="$2"
    
    local parts_count=$(yq eval '.parts | length' "$CONFIG_FILE")
    
    for ((i=0; i<parts_count; i++)); do
        local label=$(yq eval ".parts[$i].label" "$CONFIG_FILE")
        local path=$(yq eval ".parts[$i].path" "$CONFIG_FILE")
        local dest_dir="${path}/${HOSTNAME}/data/${dest_subdir}"
        
        log "INFO" "Copying $dest_subdir to $label"
        
        mkdir -p "$dest_dir"
        
        if rsync -av --delete "$source_dir/" "$dest_dir/"; then
            log "INFO" "Successfully copied $dest_subdir to $label"
        else
            handle_error "Failed to copy $dest_subdir to $label"
        fi
    done
}

# Function to create snapshots
create_snapshots() {
    log "INFO" "Creating BTRFS snapshots..."
    
    local parts_count=$(yq eval '.parts | length' "$CONFIG_FILE")
    local current_date=$(date +%Y%m%d)
    local current_week=$(date +%Y%U)
    local current_month=$(date +%Y%m)
    
    for ((i=0; i<parts_count; i++)); do
        local label=$(yq eval ".parts[$i].label" "$CONFIG_FILE")
        local path=$(yq eval ".parts[$i].path" "$CONFIG_FILE")
        local data_dir="${path}/${HOSTNAME}/data"
        local snapshots_dir="${path}/${HOSTNAME}/snapshots"
        
        log "INFO" "Creating snapshots for $label"
        
        # Create daily snapshot
        local daily_snapshot="${snapshots_dir}/daily/${current_date}_${TIMESTAMP}"
        if btrfs subvolume snapshot -r "$data_dir" "$daily_snapshot"; then
            log "INFO" "Daily snapshot created: $daily_snapshot"
        else
            handle_error "Failed to create daily snapshot for $label"
            continue
        fi
        
        # Create weekly snapshot (on Sundays)
        if [[ $(date +%u) -eq 7 ]]; then
            local weekly_snapshot="${snapshots_dir}/weekly/${current_week}_${TIMESTAMP}"
            if btrfs subvolume snapshot -r "$data_dir" "$weekly_snapshot"; then
                log "INFO" "Weekly snapshot created: $weekly_snapshot"
            else
                handle_error "Failed to create weekly snapshot for $label"
            fi
        fi
        
        # Create monthly snapshot (on the 1st of the month)
        if [[ $(date +%d) -eq 01 ]]; then
            local monthly_snapshot="${snapshots_dir}/monthly/${current_month}_${TIMESTAMP}"
            if btrfs subvolume snapshot -r "$data_dir" "$monthly_snapshot"; then
                log "INFO" "Monthly snapshot created: $monthly_snapshot"
            else
                handle_error "Failed to create monthly snapshot for $label"
            fi
        fi
    done
}

# Function to clean old snapshots according to retention policy
cleanup_old_snapshots() {
    log "INFO" "Cleaning up old snapshots..."
    
    local daily_retention=$(yq eval '.policy.daily_retention' "$CONFIG_FILE")
    local weekly_retention=$(yq eval '.policy.weekly_retention' "$CONFIG_FILE")
    local monthly_retention=$(yq eval '.policy.monthly_retention' "$CONFIG_FILE")
    
    local parts_count=$(yq eval '.parts | length' "$CONFIG_FILE")
    
    for ((i=0; i<parts_count; i++)); do
        local label=$(yq eval ".parts[$i].label" "$CONFIG_FILE")
        local path=$(yq eval ".parts[$i].path" "$CONFIG_FILE")
        local snapshots_dir="${path}/${HOSTNAME}/snapshots"
        
        log "INFO" "Cleaning snapshots for $label"
        
        # Clean daily snapshots
        if [[ -d "${snapshots_dir}/daily" ]]; then
            local daily_snapshots=($(ls -1 "${snapshots_dir}/daily" | sort -r))
            if [[ ${#daily_snapshots[@]} -gt $daily_retention ]]; then
                for ((j=$daily_retention; j<${#daily_snapshots[@]}; j++)); do
                    local snapshot_path="${snapshots_dir}/daily/${daily_snapshots[j]}"
                    log "INFO" "Removing old daily snapshot: ${daily_snapshots[j]}"
                    if btrfs subvolume delete "$snapshot_path"; then
                        log "INFO" "Deleted daily snapshot: ${daily_snapshots[j]}"
                    else
                        log "WARNING" "Failed to delete daily snapshot: ${daily_snapshots[j]}"
                    fi
                done
            fi
        fi
        
        # Clean weekly snapshots
        if [[ -d "${snapshots_dir}/weekly" ]]; then
            local weekly_snapshots=($(ls -1 "${snapshots_dir}/weekly" | sort -r))
            if [[ ${#weekly_snapshots[@]} -gt $weekly_retention ]]; then
                for ((j=$weekly_retention; j<${#weekly_snapshots[@]}; j++)); do
                    local snapshot_path="${snapshots_dir}/weekly/${weekly_snapshots[j]}"
                    log "INFO" "Removing old weekly snapshot: ${weekly_snapshots[j]}"
                    if btrfs subvolume delete "$snapshot_path"; then
                        log "INFO" "Deleted weekly snapshot: ${weekly_snapshots[j]}"
                    else
                        log "WARNING" "Failed to delete weekly snapshot: ${weekly_snapshots[j]}"
                    fi
                done
            fi
        fi
        
        # Clean monthly snapshots
        if [[ -d "${snapshots_dir}/monthly" ]]; then
            local monthly_snapshots=($(ls -1 "${snapshots_dir}/monthly" | sort -r))
            if [[ ${#monthly_snapshots[@]} -gt $monthly_retention ]]; then
                for ((j=$monthly_retention; j<${#monthly_snapshots[@]}; j++)); do
                    local snapshot_path="${snapshots_dir}/monthly/${monthly_snapshots[j]}"
                    log "INFO" "Removing old monthly snapshot: ${monthly_snapshots[j]}"
                    if btrfs subvolume delete "$snapshot_path"; then
                        log "INFO" "Deleted monthly snapshot: ${monthly_snapshots[j]}"
                    else
                        log "WARNING" "Failed to delete monthly snapshot: ${monthly_snapshots[j]}"
                    fi
                done
            fi
        fi
    done
}

# Function to send completion notification
send_completion_notification() {
    if [[ "$NOTIFICATIONS_ENABLED" == "true" ]]; then
        local status_icon
        local status_text
        
        if [[ "$BACKUP_SUCCESS" == "true" ]]; then
            status_icon="✅"
            status_text="SUCCESS"
        else
            status_icon="❌"
            status_text="FAILED"
        fi
        
        local message="$status_icon *Backup $status_text on $HOSTNAME*%0A%0A"
        message+="Time: $(date)%0A"
        message+="Duration: $(date -d@$(($(date +%s) - START_TIME)) -u +%H:%M:%S)%0A"
        
        if [[ ${#ERROR_MESSAGES[@]} -gt 0 ]]; then
            message+="%0A*Errors:*%0A"
            for error in "${ERROR_MESSAGES[@]}"; do
                message+="• $error%0A"
            done
        fi
        
        send_telegram_notification "$message"
    fi
}

# Function to unmount backup partitions
unmount_backup_partitions() {
    log "INFO" "Unmounting backup partitions..."
    
    for mount_point in "${MOUNTED_DISKS[@]}"; do
        if mountpoint -q "$mount_point"; then
            log "INFO" "Unmounting $mount_point"
            if umount "$mount_point"; then
                log "INFO" "Successfully unmounted $mount_point"
            else
                log "WARNING" "Failed to unmount $mount_point"
            fi
        fi
    done
}

# Function to cleanup temporary files
cleanup_temp_files() {
    if [[ -d "$TEMP_DIR" ]]; then
        log "INFO" "Cleaning up temporary files"
        rm -rf "$TEMP_DIR"
    fi
}

# Trap to ensure cleanup on exit
cleanup_on_exit() {
    log "INFO" "Performing cleanup on exit"
    cleanup_temp_files
    unmount_backup_partitions
}

# Main function
main() {
    local START_TIME=$(date +%s)
    
    # Set up cleanup trap
    trap cleanup_on_exit EXIT
    
    log "INFO" "Starting BTRFS backup process on $HOSTNAME"
    
    # Load environment variables
    load_env
    
    # Check configuration file
    check_config
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    
    # Step 1: Mount backup partitions
    if ! mount_backup_partitions; then
        handle_error "Failed to mount backup partitions"
        exit 1
    fi
    
    # Step 2: Verify directory structure
    verify_directory_structure
    
    # Step 3: Backup PostgreSQL
    backup_postgresql
    
    # Step 4: Backup services
    backup_services
    
    # Step 5: Backup configured paths
    backup_configured_paths
    
    # Step 6: Backup /etc
    backup_etc
    
    # Step 7: Backup certificates
    backup_certificates
    
    # Step 8: Create snapshots
    create_snapshots
    
    # Step 9: Clean old snapshots
    cleanup_old_snapshots
    
    # Step 9a: Send completion notification
    send_completion_notification
    
    # Cleanup is handled by the trap
    
    if [[ "$BACKUP_SUCCESS" == "true" ]]; then
        log "INFO" "Backup process completed successfully"
        exit 0
    else
        log "ERROR" "Backup process completed with errors"
        exit 1
    fi
}

# Entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi