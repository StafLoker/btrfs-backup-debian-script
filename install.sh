#!/bin/bash

# BTRFS Backup Installer Script
# Repository: https://github.com/StafLoker/btrfs-backup-debian-script
# Usage: sudo bash <(curl -Ls "https://raw.githubusercontent.com/StafLoker/btrfs-backup-debian-script/main/install.sh")

set -euo pipefail

# Color Definitions
readonly RED='\033[31m'
readonly YELLOW='\033[33m'
readonly GREEN='\033[32m'
readonly PURPLE='\033[36m'
readonly BLUE='\033[34m'
readonly RESET='\033[0m'

# Configuration
readonly CONFIG_FILE="/etc/btrfs-backup/config.yaml"
readonly CONFIG_DIR="/etc/btrfs-backup"
readonly LOG_FILE="/var/log/backup_$(hostname).log"
readonly SERVICE_NAME="backup-$(hostname)"
readonly INSTALL_DIR="/opt/btrfs-backup"
readonly SCRIPT_NAME="backup.sh"
readonly ENV_FILE="/etc/btrfs-backup/.env"

# Function to print INFO messages
log_info() {
    echo -e "${YELLOW}[INFO] $1${RESET}"
}

# Function to print SUCCESS messages
log_success() {
    echo -e "${GREEN}[SUCCESS] $1${RESET}"
}

# Function to print ERROR messages
log_error() {
    echo -e "${RED}[ERROR] $1${RESET}"
}

# Function to print WARNING messages
log_warning() {
    echo -e "${PURPLE}[WARNING] $1${RESET}"
}

# Function to print DEBUG messages
log_debug() {
    echo -e "${BLUE}[DEBUG] $1${RESET}"
}

# Function to ask yes/no questions
ask_yes_no() {
    local question="$1"
    local default="${2:-n}"
    local answer
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -p "$question [Y/n]: " answer
            answer=${answer:-y}
        else
            read -p "$question [y/N]: " answer
            answer=${answer:-n}
        fi
        
        case ${answer,,} in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) log_warning "Please answer 'y' or 'n'" ;;
        esac
    done
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        log_info "Use: sudo bash <(curl -Ls \"https://raw.githubusercontent.com/StafLoker/btrfs-backup-debian-script/main/install.sh\")"
        exit 1
    fi
}

# Function to check and install dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    
    local dependencies=("curl" "sed" "yq" "btrfs")
    local missing_deps=()
    
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_warning "Missing dependencies: ${missing_deps[*]}"
        
        if ask_yes_no "Do you want to install missing dependencies?"; then
            log_info "Installing dependencies..."
            apt-get update
            
            for dep in "${missing_deps[@]}"; do
                case "$dep" in
                    "yq")
                        log_info "Installing yq..."
                        wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
                        chmod +x /usr/local/bin/yq
                        ;;
                    "btrfs")
                        log_info "Installing btrfs-progs..."
                        apt-get install -y btrfs-progs
                        ;;
                    *)
                        log_info "Installing $dep..."
                        apt-get install -y "$dep"
                        ;;
                esac
            done
            
            log_success "Dependencies installed successfully"
        else
            log_error "Cannot install dependencies. Aborting installation."
            exit 1
        fi
    else
        log_success "All dependencies are installed"
    fi
}

# Function to initialize config structure
init_config() {
    log_info "Initializing configuration..."
    
    # Create config directory
    mkdir -p "$CONFIG_DIR"
    
    # Create basic config if it doesn't exist
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_info "Creating initial configuration file..."
        cat > "$CONFIG_FILE" <<EOF
parts: []
policy:
  daily_retention: 7
  weekly_retention: 4
  monthly_retention: 12
backups:
  postgresql: false
  paths: []
  etc: false
  docker: false
  certificates: false
notifications: false
EOF
        log_success "Configuration file created: $CONFIG_FILE"
    else
        log_info "Existing configuration file found"
    fi
}

# Function to configure backup parts (disks)
configure_parts() {
    log_info "Configuring backup disks..."
    
    # Get existing parts
    local existing_parts=$(yq eval '.parts | length' "$CONFIG_FILE")
    
    if [[ $existing_parts -eq 0 ]]; then
        log_info "No disks configured. Setting up backup disks..."
        
        local parts_array=""
        local part_count=1
        
        while true; do
            echo
            log_info "Configuring backup disk #$part_count"
            
            read -p "Disk label (e.g., backup_1): " label
            read -p "Mount path (e.g., /mnt/backups/disk_1): " path
            read -p "Device (e.g., /dev/sdc1): " dev
            
            # Add to parts array
            if [[ -n "$parts_array" ]]; then
                parts_array="${parts_array}, "
            fi
            parts_array="${parts_array}{\"label\": \"$label\", \"path\": \"$path\", \"dev\": \"$dev\"}"
            
            if ! ask_yes_no "Do you want to add another backup disk?"; then
                break
            fi
            
            ((part_count++))
        done
        
        # Update config
        yq eval ".parts = [$parts_array]" -i "$CONFIG_FILE"
        log_success "Backup disks configured"
    else
        log_info "Already have $existing_parts disk(s) configured"
    fi
}

# Function to mount and verify disks
mount_and_verify_disks() {
    log_info "Verifying and mounting disks..."
    
    local parts_count=$(yq eval '.parts | length' "$CONFIG_FILE")
    
    for ((i=0; i<parts_count; i++)); do
        local label=$(yq eval ".parts[$i].label" "$CONFIG_FILE")
        local path=$(yq eval ".parts[$i].path" "$CONFIG_FILE")
        local dev=$(yq eval ".parts[$i].dev" "$CONFIG_FILE")
        
        log_info "Processing disk: $label ($dev -> $path)"
        
        # Create mount point
        mkdir -p "$path"
        
        # Check if already mounted
        if ! mountpoint -q "$path"; then
            log_info "Mounting $dev to $path..."
            if ! mount "$dev" "$path"; then
                log_error "Could not mount $dev to $path"
                exit 1
            fi
        else
            log_info "Disk already mounted at $path"
        fi
        
        # Verify and create directory structure
        local host_dir="${path}/${HOSTNAME}"
        local data_dir="${host_dir}/data"
        local snapshots_dir="${host_dir}/snapshots"
        
        log_info "Creating directory structure for $label..."
        
        # Create host directory
        mkdir -p "$host_dir"
        
        # Create data subvolume if it doesn't exist
        if [[ ! -d "$data_dir" ]]; then
            log_info "Creating data subvolume: $data_dir"
            btrfs subvolume create "$data_dir"
        fi
        
        # Create snapshots directories
        mkdir -p "$snapshots_dir"/{daily,weekly,monthly}
        
        log_success "Directory structure created for $label"
    done
}

# Function to configure retention policy
configure_policy() {
    log_info "Configuring retention policy..."
    
    local current_daily=$(yq eval '.policy.daily_retention' "$CONFIG_FILE")
    local current_weekly=$(yq eval '.policy.weekly_retention' "$CONFIG_FILE")
    local current_monthly=$(yq eval '.policy.monthly_retention' "$CONFIG_FILE")
    
    log_info "Current configuration - Daily: $current_daily, Weekly: $current_weekly, Monthly: $current_monthly"
    
    if ask_yes_no "Do you want to change the retention policy?"; then
        read -p "Daily retention (days) [$current_daily]: " daily
        read -p "Weekly retention (weeks) [$current_weekly]: " weekly  
        read -p "Monthly retention (months) [$current_monthly]: " monthly
        
        daily=${daily:-$current_daily}
        weekly=${weekly:-$current_weekly}
        monthly=${monthly:-$current_monthly}
        
        yq eval ".policy.daily_retention = $daily" -i "$CONFIG_FILE"
        yq eval ".policy.weekly_retention = $weekly" -i "$CONFIG_FILE"
        yq eval ".policy.monthly_retention = $monthly" -i "$CONFIG_FILE"
        
        log_success "Retention policy updated"
    fi
}

# Function to configure PostgreSQL backup
configure_postgresql() {
    log_info "Configuring PostgreSQL backup..."
    
    local current_pg=$(yq eval '.backups.postgresql' "$CONFIG_FILE")
    
    if [[ "$current_pg" == "false" ]]; then
        if ask_yes_no "Do you want to backup PostgreSQL?"; then
            yq eval '.backups.postgresql = true' -i "$CONFIG_FILE"
            log_success "PostgreSQL backup enabled"
        fi
    else
        log_info "PostgreSQL backup already enabled"
    fi
}

# Function to configure path backups
configure_paths() {
    log_info "Configuring paths for backup..."
    
    local existing_paths=$(yq eval '.backups.paths | length' "$CONFIG_FILE")
    
    if [[ $existing_paths -eq 0 ]] || ask_yes_no "Do you want to add more paths for backup?"; then
        while true; do
            echo
            read -p "Path to backup (e.g., /home/user/photos): " backup_path
            
            if [[ -n "$backup_path" ]]; then
                read -p "Label for this path (optional): " path_label
                read -p "Associated systemd service (optional): " systemd_service
                
                # Build path object
                local path_obj="{\"path\": \"$backup_path\""
                if [[ -n "$path_label" ]]; then
                    path_obj="${path_obj}, \"label\": \"$path_label\""
                fi
                if [[ -n "$systemd_service" ]]; then
                    path_obj="${path_obj}, \"systemd\": \"$systemd_service\""
                fi
                path_obj="${path_obj}}"
                
                # Add to config
                yq eval ".backups.paths += [$path_obj]" -i "$CONFIG_FILE"
                log_success "Path added: $backup_path"
            fi
            
            if ! ask_yes_no "Do you want to add another path?"; then
                break
            fi
        done
    fi
}

# Function to configure etc backup
configure_etc() {
    log_info "Configuring /etc backup..."
    
    local current_etc=$(yq eval '.backups.etc' "$CONFIG_FILE")
    
    if [[ "$current_etc" == "false" ]]; then
        if ask_yes_no "Do you want to backup /etc?"; then
            yq eval '.backups.etc = true' -i "$CONFIG_FILE"
            log_success "/etc backup enabled"
        fi
    else
        log_info "/etc backup already enabled"
    fi
}

# Function to configure Docker backup
configure_docker() {
    log_info "Configuring Docker backup..."
    
    local current_docker=$(yq eval '.backups.docker' "$CONFIG_FILE")
    
    if [[ "$current_docker" == "false" ]]; then
        if command -v docker &>/dev/null; then
            if ask_yes_no "Do you want to backup Docker?"; then
                yq eval '.backups.docker = true' -i "$CONFIG_FILE"
                log_success "Docker backup enabled"
            fi
        else
            log_info "Docker not installed, skipping configuration"
        fi
    else
        log_info "Docker backup already enabled"
    fi
}

# Function to configure certificates backup
configure_certificates() {
    log_info "Configuring certificates backup..."
    
    local current_certs=$(yq eval '.backups.certificates' "$CONFIG_FILE")
    
    if [[ "$current_certs" == "false" ]]; then
        if ask_yes_no "Do you want to backup SSL certificates?"; then
            yq eval '.backups.certificates = true' -i "$CONFIG_FILE"
            log_success "Certificates backup enabled"
        fi
    else
        log_info "Certificates backup already enabled"
    fi
}

# Function to configure notifications
configure_notifications() {
    log_info "Configuring notifications..."
    
    local current_notifications=$(yq eval '.notifications' "$CONFIG_FILE")
    
    if [[ "$current_notifications" == "false" ]]; then
        if ask_yes_no "Do you want to enable Telegram notifications?"; then
            yq eval '.notifications = true' -i "$CONFIG_FILE"
            
            echo
            log_info "Configuring Telegram bot..."
            read -p "Telegram bot token: " bot_token
            read -p "Telegram chat ID: " chat_id
            
            # Create .env file
            cat > "$ENV_FILE" <<EOF
TELEGRAM_BOT_TOKEN=$bot_token
TELEGRAM_CHAT_ID=$chat_id
EOF
            
            chmod 600 "$ENV_FILE"
            log_success "Telegram notifications configured"
        fi
    else
        log_info "Notifications already enabled"
    fi
}

# Function to display final configuration
display_config() {
    log_info "Final configuration:"
    echo
    cat "$CONFIG_FILE"
    echo
}

# Function to download scripts
download_scripts() {
    log_info "Downloading scripts from repository..."
    
    # Create install directory
    mkdir -p "$INSTALL_DIR"
    
    # Download main script
    local repo_url="https://raw.githubusercontent.com/StafLoker/btrfs-backup-debian-script/main"
    
    curl -Ls "$repo_url/backup.sh" -o "$INSTALL_DIR/$SCRIPT_NAME"
    curl -Ls "$repo_url/README.md" -o "$INSTALL_DIR/README.md"
    curl -Ls "$repo_url/LICENSE" -o "$INSTALL_DIR/LICENSE"
    
    # Make script executable
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
    
    # Create symlink
    ln -sf "$INSTALL_DIR/$SCRIPT_NAME" "/usr/local/bin/$SERVICE_NAME.sh"
    
    log_success "Scripts downloaded and configured"
}

# Function to configure logging
configure_logging() {
    log_info "Configuring logging system..."
    
    # Create log file
    touch "$LOG_FILE"
    
    # Configure logrotate
    log_info "Configuring log rotation..."
    cat > "/etc/logrotate.d/$SERVICE_NAME" <<EOF
$LOG_FILE {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF
    
    log_success "Logging system configured"
}

# Function to create systemd service and timer
create_systemd_service() {
    log_info "Creating systemd service and timer..."
    
    # Create service file
    cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=BTRFS Backup Service for $(hostname)
After=network.target postgresql.service docker.service
Wants=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/$SERVICE_NAME.sh
User=root
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE
TimeoutStartSec=7200
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=-$ENV_FILE
EOF
    
    # Ask for cron expression
    echo
    log_info "Configuring backup schedule..."
    echo "Cron expression examples:"
    echo "  *-*-* 04:00:00    - Every day at 4:00 AM"
    echo "  *-*-* 02:30:00    - Every day at 2:30 AM"
    echo "  Sun *-*-* 03:00:00 - Every Sunday at 3:00 AM"
    echo
    
    read -p "Time expression for backup [*-*-* 04:00:00]: " cron_expression
    cron_expression=${cron_expression:-"*-*-* 04:00:00"}
    
    # Create timer file
    cat > "/etc/systemd/system/$SERVICE_NAME.timer" <<EOF
[Unit]
Description=Run $SERVICE_NAME.service at scheduled time
Requires=$SERVICE_NAME.service

[Timer]
OnCalendar=$cron_expression
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF
    
    # Reload systemd and enable timer
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME.timer"
    systemctl start "$SERVICE_NAME.timer"
    
    log_success "Service and timer created and enabled"
    log_info "Timer scheduled for: $cron_expression"
}

# Function to run initial backup
run_initial_backup() {
    if ask_yes_no "Do you want to run an initial backup now?"; then
        log_info "Running initial backup..."
        
        if "/usr/local/bin/$SERVICE_NAME.sh"; then
            log_success "Initial backup completed"
        else
            log_error "Initial backup failed. Check logs at $LOG_FILE"
        fi
    fi
}

# Function to unmount disks
unmount_disks() {
    log_info "Unmounting disks..."
    
    local parts_count=$(yq eval '.parts | length' "$CONFIG_FILE")
    
    for ((i=0; i<parts_count; i++)); do
        local path=$(yq eval ".parts[$i].path" "$CONFIG_FILE")
        local label=$(yq eval ".parts[$i].label" "$CONFIG_FILE")
        
        if mountpoint -q "$path"; then
            log_info "Unmounting $label ($path)..."
            umount "$path" || log_warning "Could not unmount $path"
        fi
    done
}

# Function to show final status
show_final_status() {
    echo
    log_success "Installation completed!"
    echo
    log_info "Installation summary:"
    echo "  - Configuration file: $CONFIG_FILE"
    echo "  - Scripts installed at: $INSTALL_DIR"
    echo "  - Log file: $LOG_FILE"
    echo "  - Systemd service: $SERVICE_NAME.service"
    echo "  - Systemd timer: $SERVICE_NAME.timer"
    echo
    log_info "Useful commands:"
    echo "  - Check timer status: systemctl status $SERVICE_NAME.timer"
    echo "  - View logs: tail -f $LOG_FILE"
    echo "  - Run manual backup: sudo $SERVICE_NAME.sh"
    echo "  - Edit configuration: sudo nano $CONFIG_FILE"
    echo
}

# Main function
main() {
    log_info "Starting BTRFS Backup installation..."
    
    # Check if running as root
    check_root
    
    # Step 1: Check dependencies
    check_dependencies
    
    # Step 2: Initialize configuration
    init_config
    
    # Step 3: Configure backup parts (disks)
    configure_parts
    
    # Step 4: Mount and verify disks
    mount_and_verify_disks
    
    # Step 5: Configure retention policy
    configure_policy
    
    # Step 6: Configure PostgreSQL backup
    configure_postgresql
    
    # Step 7: Configure path backups
    configure_paths
    
    # Step 8: Configure /etc backup
    configure_etc
    
    # Step 9: Configure Docker backup
    configure_docker
    
    # Step 10: Configure certificates backup
    configure_certificates
    
    # Step 10a: Configure notifications
    configure_notifications
    
    # Step 11: Display final configuration
    display_config
    
    # Step 11a: Download scripts
    download_scripts
    
    # Step 12: Configure logging
    configure_logging
    
    # Step 13: Create systemd service and timer
    create_systemd_service
    
    # Step 14: Run initial backup
    run_initial_backup
    
    # Step 15: Unmount disks
    unmount_disks
    
    # Show final status
    show_final_status
}

# Run main function
main "$@"