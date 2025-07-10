#!/bin/bash

# BTRFS Backup Installer Script
# Repository: https://github.com/StafLoker/btrfs-backup-debian-script
# Usage: sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/StafLoker/btrfs-backup-debian-script/main/install.sh)"

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
        y | yes) return 0 ;;
        n | no) return 1 ;;
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

    local dependencies=("curl" "wget" "sed" "tar" "yq" "rsync")
    local missing_deps=()

    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_warning "Missing dependencies: ${missing_deps[*]}"

        if ask_yes_no "Do you want to install missing dependencies?" "y"; then
            log_info "Installing dependencies..."
            apt-get update

            for dep in "${missing_deps[@]}"; do
                case "$dep" in
                "yq")
                    log_info "Installing the correct yq version (mikefarah/yq)..."

                    # Detect architecture
                    local ARCH=$(uname -m)
                    local YQ_VERSION="v4.45.4"
                    local YQ_BINARY

                    case $ARCH in
                    x86_64)
                        YQ_BINARY="yq_linux_amd64"
                        ;;
                    aarch64 | arm64)
                        YQ_BINARY="yq_linux_arm64"
                        ;;
                    armv7l | armv6l)
                        YQ_BINARY="yq_linux_arm"
                        ;;
                    i386 | i686)
                        YQ_BINARY="yq_linux_386"
                        ;;
                    *)
                        log_error "Unsupported architecture: $ARCH"
                        exit 1
                        ;;
                    esac

                    log_info "Detected architecture: $ARCH"
                    log_info "Downloading yq ${YQ_VERSION} (${YQ_BINARY})..."
                    wget -O /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}"
                    chmod +x /usr/local/bin/yq

                    # Verify installation
                    if /usr/local/bin/yq --version &>/dev/null; then
                        log_success "yq installed successfully"
                    else
                        log_error "Failed to install yq"
                        exit 1
                    fi
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
            log_error "Cannot continue without dependencies. Aborting installation."
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
        cat >"$CONFIG_FILE" <<EOF
parts: []
notifications: false
policy:
  daily_retention: 7
  weekly_retention: 4
  monthly_retention: 12
backups:
  infrastructure:
    postgresql:
      global: false
      all_db: false
      config: false
    nginx:
      config: false
      certificates: false
    redis:
      config: false
    meilisearch:
      config: false
      data: false
  services: []
  paths: []
  etc: false
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

    for ((i = 0; i < parts_count; i++)); do
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

# Function to configure PostgreSQL infrastructure
configure_postgresql_infrastructure() {
    log_info "Configuring PostgreSQL infrastructure..."

    local current_global=$(yq eval '.backups.infrastructure.postgresql.global // false' "$CONFIG_FILE")
    local current_all_db=$(yq eval '.backups.infrastructure.postgresql.all_db // false' "$CONFIG_FILE")
    local current_config=$(yq eval '.backups.infrastructure.postgresql.config // false' "$CONFIG_FILE")

    log_info "Current PostgreSQL configuration:"
    log_info "  Global backup: $current_global"
    log_info "  All databases: $current_all_db"
    log_info "  Configuration: $current_config"

    if ask_yes_no "Do you want to configure PostgreSQL infrastructure backup?"; then
        # Configure global backup
        if ask_yes_no "Enable PostgreSQL global backup (roles, users)?"; then
            yq eval '.backups.infrastructure.postgresql.global = true' -i "$CONFIG_FILE"
            log_success "PostgreSQL global backup enabled"
        fi

        # Configure all databases backup
        if ask_yes_no "Enable backup of all PostgreSQL databases?"; then
            yq eval '.backups.infrastructure.postgresql.all_db = true' -i "$CONFIG_FILE"
            log_success "PostgreSQL all databases backup enabled"
        fi

        # Configure configuration backup
        if ask_yes_no "Enable PostgreSQL configuration backup (/etc/postgresql)?"; then
            yq eval '.backups.infrastructure.postgresql.config = true' -i "$CONFIG_FILE"
            log_success "PostgreSQL configuration backup enabled"
        fi
    fi
}

# Function to configure Nginx infrastructure
configure_nginx_infrastructure() {
    log_info "Configuring Nginx infrastructure..."

    local current_config=$(yq eval '.backups.infrastructure.nginx.config // false' "$CONFIG_FILE")
    local current_certs=$(yq eval '.backups.infrastructure.nginx.certificates // false' "$CONFIG_FILE")

    log_info "Current Nginx configuration:"
    log_info "  Configuration backup: $current_config"
    log_info "  Certificates backup: $current_certs"

    if ask_yes_no "Do you want to configure Nginx infrastructure backup?"; then
        # Configure configuration backup
        if ask_yes_no "Enable Nginx configuration backup (/etc/nginx)?"; then
            yq eval '.backups.infrastructure.nginx.config = true' -i "$CONFIG_FILE"
            log_success "Nginx configuration backup enabled"
        fi

        # Configure certificates backup
        if ask_yes_no "Enable Nginx certificates backup (from sites-available)?"; then
            yq eval '.backups.infrastructure.nginx.certificates = true' -i "$CONFIG_FILE"
            log_success "Nginx certificates backup enabled"
            log_info "This will analyze nginx sites and backup only certificates in use"
        fi
    fi
}

# Function to configure Redis infrastructure
configure_redis_infrastructure() {
    log_info "Configuring Redis infrastructure..."

    local current_config=$(yq eval '.backups.infrastructure.redis.config // false' "$CONFIG_FILE")

    log_info "Current Redis configuration:"
    log_info "  Configuration backup: $current_config"

    if ask_yes_no "Do you want to configure Redis infrastructure backup?"; then
        if ask_yes_no "Enable Redis configuration backup (/etc/redis)?"; then
            yq eval '.backups.infrastructure.redis.config = true' -i "$CONFIG_FILE"
            log_success "Redis configuration backup enabled"
        fi
    fi
}

# Function to configure Meilisearch infrastructure
configure_meilisearch_infrastructure() {
    log_info "Configuring Meilisearch infrastructure..."

    local current_config=$(yq eval '.backups.infrastructure.meilisearch.config // false' "$CONFIG_FILE")
    local current_data=$(yq eval '.backups.infrastructure.meilisearch.data // false' "$CONFIG_FILE")

    log_info "Current Meilisearch configuration:"
    log_info "  Configuration backup: $current_config"
    log_info "  Data backup: $current_data"

    if ask_yes_no "Do you want to configure Meilisearch infrastructure backup?"; then
        if ask_yes_no "Enable Meilisearch configuration backup (/etc/meilisearch)?"; then
            yq eval '.backups.infrastructure.meilisearch.config = true' -i "$CONFIG_FILE"
            log_success "Meilisearch configuration backup enabled"
        fi

        if ask_yes_no "Enable Meilisearch data backup (/var/lib/meilisearch)?"; then
            yq eval '.backups.infrastructure.meilisearch.data = true' -i "$CONFIG_FILE"
            log_success "Meilisearch data backup enabled"
        fi
    fi
}

# Function to detect user services
detect_user_services() {
    local user_name="$1"
    local uid="$2"

    log_info "Detecting user services for user: $user_name (UID: $uid)"

    # Get user services using runuser to ensure proper environment
    local user_services
    if user_services=$(runuser -l "$user_name" -c "systemctl --user list-units --type=service --state=running --no-legend" 2>/dev/null); then
        if [[ -n "$user_services" ]]; then
            echo "Available user services for $user_name:"
            echo "$user_services" | awk '{print "  - " $1}'
            return 0
        else
            log_info "No running user services found for $user_name"
            return 1
        fi
    else
        log_warning "Could not retrieve user services for $user_name"
        return 1
    fi
}

# Function to configure services backup
configure_services() {
    log_info "Configuring services backup..."

    local existing_services=$(yq eval '.backups.services | length' "$CONFIG_FILE")

    if [[ $existing_services -eq 0 ]] || ask_yes_no "Do you want to add/configure services for backup?"; then
        while true; do
            echo
            log_info "Configuring service backup..."

            # Get mandatory fields
            read -p "Service label (mandatory, e.g., gitea): " service_label
            if [[ -z "$service_label" ]]; then
                log_warning "Service label is mandatory"
                continue
            fi

            echo
            log_info "Service type selection:"
            echo "1. System service (runs as root)"
            echo "2. User service (runs as specific user, e.g., Podman containers)"

            local service_type
            while true; do
                read -p "Select service type [1-2]: " service_type
                case "$service_type" in
                1) break ;;
                2) break ;;
                *) log_warning "Please select 1 or 2" ;;
                esac
            done

            local systemd_service=""
            local user_name=""
            local uid=""

            if [[ "$service_type" == "1" ]]; then
                # System service
                read -p "Systemd service name (e.g., gitea.service): " systemd_service
                if [[ -z "$systemd_service" ]]; then
                    log_warning "Systemd service name is mandatory"
                    continue
                fi

                # Remove .service suffix if present
                systemd_service=${systemd_service%.service}

                # Check if service exists
                if ! systemctl list-unit-files "${systemd_service}.service" &>/dev/null; then
                    log_warning "Warning: Service ${systemd_service}.service not found in systemctl"
                    if ! ask_yes_no "Do you want to continue anyway?"; then
                        continue
                    fi
                fi
            else
                # User service
                read -p "User name (e.g., stefan): " user_name
                if [[ -z "$user_name" ]]; then
                    log_warning "User name is mandatory for user services"
                    continue
                fi

                # Check if user exists and get UID
                if ! id "$user_name" &>/dev/null; then
                    log_warning "User $user_name does not exist"
                    continue
                fi

                uid=$(id -u "$user_name")
                log_info "User $user_name found with UID: $uid"

                # Try to detect user services
                echo
                if detect_user_services "$user_name" "$uid"; then
                    echo
                fi

                read -p "User systemd service name (e.g., podman-compose@linkwarden): " systemd_service
                if [[ -z "$systemd_service" ]]; then
                    log_warning "Systemd service name is mandatory"
                    continue
                fi

                # Check if user service exists
                if ! runuser -l "$user_name" -c "systemctl --user list-unit-files '$systemd_service.service'" &>/dev/null 2>&1; then
                    log_warning "Warning: User service $systemd_service.service not found for user $user_name"
                    if ! ask_yes_no "Do you want to continue anyway?"; then
                        continue
                    fi
                fi
            fi

            # Build service object starting with mandatory fields
            local service_obj=""
            if [[ "$service_type" == "1" ]]; then
                # System service format
                service_obj="{\"label\": \"$service_label\", \"systemd\": {\"name\": \"$systemd_service\"}"
            else
                # User service format
                service_obj="{\"label\": \"$service_label\", \"systemd\": {\"name\": \"$systemd_service\", \"podman\": {\"user\": \"$user_name\", \"uid\": $uid}}"
            fi

            # Get optional fields
            echo
            log_info "Optional configurations for $service_label:"

            # Container configuration (replaces docker_compose)
            if ask_yes_no "Does this service use containers (Docker/Podman Compose)?"; then
                read -p "Container compose directory path (e.g., /opt/$service_label): " compose_path
                if [[ -n "$compose_path" ]]; then
                    if [[ -d "$compose_path" ]]; then
                        service_obj="${service_obj}, \"containers\": {\"compose\": \"$compose_path\"}"
                        log_success "Container compose path added: $compose_path"
                    else
                        log_warning "Directory $compose_path does not exist"
                        if ask_yes_no "Add it anyway?"; then
                            service_obj="${service_obj}, \"containers\": {\"compose\": \"$compose_path\"}"
                        fi
                    fi
                fi
            fi

            # Configuration directory
            if ask_yes_no "Does this service have a configuration directory to backup?"; then
                read -p "Configuration directory path (e.g., /etc/$service_label): " config_path
                if [[ -n "$config_path" ]]; then
                    if [[ -d "$config_path" ]]; then
                        service_obj="${service_obj}, \"config\": \"$config_path\""
                        log_success "Configuration path added: $config_path"
                    else
                        log_warning "Directory $config_path does not exist"
                        if ask_yes_no "Add it anyway?"; then
                            service_obj="${service_obj}, \"config\": \"$config_path\""
                        fi
                    fi
                fi
            fi

            # Data configuration (files and/or database)
            local has_data=false
            if ask_yes_no "Does this service have data files to backup?"; then
                read -p "Data files directory path (e.g., /var/lib/$service_label): " data_files_path
                if [[ -n "$data_files_path" ]]; then
                    if [[ -d "$data_files_path" ]]; then
                        service_obj="${service_obj}, \"data\": {\"files\": \"$data_files_path\""
                        has_data=true
                        log_success "Data files path added: $data_files_path"
                    else
                        log_warning "Directory $data_files_path does not exist"
                        if ask_yes_no "Add it anyway?"; then
                            service_obj="${service_obj}, \"data\": {\"files\": \"$data_files_path\""
                            has_data=true
                        fi
                    fi
                fi
            fi

            # PostgreSQL database
            if ask_yes_no "Does this service use a PostgreSQL database?"; then
                read -p "PostgreSQL database name (e.g., ${service_label}db): " pg_database
                if [[ -n "$pg_database" ]]; then
                    # Check if database exists
                    if command -v sudo &>/dev/null && sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$pg_database" 2>/dev/null; then
                        log_success "Database $pg_database found"
                    else
                        log_warning "Database $pg_database not found or PostgreSQL not accessible"
                        if ! ask_yes_no "Add it anyway?"; then
                            pg_database=""
                        fi
                    fi

                    if [[ -n "$pg_database" ]]; then
                        if [[ "$has_data" == "true" ]]; then
                            service_obj="${service_obj}, \"pg-db\": \"$pg_database\"}"
                        else
                            service_obj="${service_obj}, \"data\": {\"pg-db\": \"$pg_database\"}"
                            has_data=true
                        fi
                        log_success "PostgreSQL database added: $pg_database"
                    fi
                fi
            fi

            # Close data object if it was opened
            if [[ "$has_data" == "true" ]] && [[ "$service_obj" =~ \"data\".*\{[^}]*$ ]]; then
                service_obj="${service_obj}}"
            fi

            # Logs directory
            if ask_yes_no "Does this service have logs to backup?"; then
                read -p "Logs directory path (e.g., /var/log/$service_label): " logs_path
                if [[ -n "$logs_path" ]]; then
                    if [[ -d "$logs_path" ]]; then
                        service_obj="${service_obj}, \"logs\": \"$logs_path\""
                        log_success "Logs path added: $logs_path"
                    else
                        log_warning "Directory $logs_path does not exist"
                        if ask_yes_no "Add it anyway?"; then
                            service_obj="${service_obj}, \"logs\": \"$logs_path\""
                        fi
                    fi
                fi
            fi

            # Close service object
            service_obj="${service_obj}}"

            # Validate that at least one optional field was added
            if [[ ! "$service_obj" =~ (containers|config|data|logs) ]]; then
                log_warning "Service $service_label has no backup components configured"
                if ! ask_yes_no "Do you want to add it anyway?"; then
                    continue
                fi
            fi

            # Add service to config
            yq eval ".backups.services += [$service_obj]" -i "$CONFIG_FILE"
            log_success "Service added: $service_label"

            # Show what was configured
            echo
            log_info "Service $service_label configuration:"
            if [[ "$service_type" == "1" ]]; then
                echo "  - Type: System service"
                echo "  - Systemd service: $systemd_service"
            else
                echo "  - Type: User service"
                echo "  - Systemd service: $systemd_service"
                echo "  - User: $user_name (UID: $uid)"
            fi

            if [[ "$service_obj" =~ \"compose\" ]]; then
                local comp_path=$(echo "$service_obj" | grep -o '"compose": "[^"]*"' | cut -d'"' -f4)
                echo "  - Container Compose: $comp_path"
            fi
            if [[ "$service_obj" =~ \"config\" ]]; then
                local cfg_path=$(echo "$service_obj" | grep -o '"config": "[^"]*"' | cut -d'"' -f4)
                echo "  - Configuration: $cfg_path"
            fi
            if [[ "$service_obj" =~ \"files\" ]]; then
                local files_path=$(echo "$service_obj" | grep -o '"files": "[^"]*"' | cut -d'"' -f4)
                echo "  - Data files: $files_path"
            fi
            if [[ "$service_obj" =~ \"pg-db\" ]]; then
                local db_name=$(echo "$service_obj" | grep -o '"pg-db": "[^"]*"' | cut -d'"' -f4)
                echo "  - PostgreSQL DB: $db_name"
            fi
            if [[ "$service_obj" =~ \"logs\" ]]; then
                local logs_path=$(echo "$service_obj" | grep -o '"logs": "[^"]*"' | cut -d'"' -f4)
                echo "  - Logs: $logs_path"
            fi

            if ! ask_yes_no "Do you want to add another service?"; then
                break
            fi
        done

        log_success "Services configuration completed"
    else
        local service_count=$(yq eval '.backups.services | length' "$CONFIG_FILE")
        log_info "Already have $service_count service(s) configured"

        # Show configured services
        if [[ $service_count -gt 0 ]]; then
            echo
            log_info "Currently configured services:"
            for ((i = 0; i < service_count; i++)); do
                local label=$(yq eval ".backups.services[$i].label" "$CONFIG_FILE")
                local systemd_name=$(yq eval ".backups.services[$i].systemd.name" "$CONFIG_FILE")
                local user=$(yq eval ".backups.services[$i].systemd.podman.user // \"system\"" "$CONFIG_FILE")
                if [[ "$user" == "system" || "$user" == "null" ]]; then
                    echo "  - $label (systemd: $systemd_name, type: system)"
                else
                    echo "  - $label (systemd: $systemd_name, user: $user)"
                fi
            done
        fi
    fi
}

# Function to configure path backups
# Function to configure path backups
configure_paths() {
    log_info "Configuring paths for backup..."

    local existing_paths=$(yq eval '.backups.paths | length' "$CONFIG_FILE")

    # Show existing paths if any
    if [[ $existing_paths -gt 0 ]]; then
        echo
        log_info "Currently configured paths:"
        for ((i = 0; i < existing_paths; i++)); do
            local label=$(yq eval ".backups.paths[$i].label" "$CONFIG_FILE")
            local path=$(yq eval ".backups.paths[$i].path" "$CONFIG_FILE")
            echo "  - $label: $path"
        done
        echo
    fi

    # Always ask if user wants to add paths (new or additional)
    local question_text=""
    if [[ $existing_paths -eq 0 ]]; then
        question_text="Do you want to add paths for backup?"
    else
        question_text="Do you want to add more paths for backup?"
    fi

    if ask_yes_no "$question_text"; then
        while true; do
            echo
            read -p "Path to backup (e.g., /home/user/photos): " backup_path

            if [[ -n "$backup_path" ]]; then
                # Check if path exists
                if [[ -d "$backup_path" ]]; then
                    log_success "Path exists: $backup_path"
                elif [[ -e "$backup_path" ]]; then
                    log_warning "Path exists but is not a directory: $backup_path"
                    if ! ask_yes_no "Continue anyway?"; then
                        continue
                    fi
                else
                    log_warning "Path does not exist: $backup_path"
                    if ! ask_yes_no "Add it anyway?"; then
                        continue
                    fi
                fi

                read -p "Label for this path (mandatory): " path_label

                if [[ -z "$path_label" ]]; then
                    log_warning "Label is mandatory for paths"
                    continue
                fi

                # Check if label already exists
                local label_exists=false
                for ((i = 0; i < existing_paths; i++)); do
                    local existing_label=$(yq eval ".backups.paths[$i].label" "$CONFIG_FILE")
                    if [[ "$existing_label" == "$path_label" ]]; then
                        label_exists=true
                        break
                    fi
                done

                if [[ "$label_exists" == "true" ]]; then
                    log_warning "Label '$path_label' already exists"
                    if ! ask_yes_no "Use a different label?"; then
                        continue
                    else
                        continue
                    fi
                fi

                # Build path object
                local path_obj="{\"label\": \"$path_label\", \"path\": \"$backup_path\"}"

                # Add to config
                yq eval ".backups.paths += [$path_obj]" -i "$CONFIG_FILE"
                log_success "Path added: $backup_path (label: $path_label)"
                
                # Update existing_paths count for label checking
                ((existing_paths++))
            else
                log_warning "Path cannot be empty"
                continue
            fi

            if ! ask_yes_no "Do you want to add another path?"; then
                break
            fi
        done

        # Show final configuration
        local final_paths=$(yq eval '.backups.paths | length' "$CONFIG_FILE")
        if [[ $final_paths -gt 0 ]]; then
            echo
            log_success "Final paths configuration:"
            for ((i = 0; i < final_paths; i++)); do
                local label=$(yq eval ".backups.paths[$i].label" "$CONFIG_FILE")
                local path=$(yq eval ".backups.paths[$i].path" "$CONFIG_FILE")
                echo "  - $label: $path"
            done
        fi
    else
        if [[ $existing_paths -eq 0 ]]; then
            log_info "No paths will be configured for backup"
        else
            log_info "Keeping existing $existing_paths path(s) configured"
        fi
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

# Function to configure notifications
configure_notifications() {
    log_info "Configuring notifications..."

    local current_notifications=$(yq eval '.notifications' "$CONFIG_FILE")
    local env_exists=false
    local current_bot_token=""
    local current_chat_id=""
    local config_complete=false

    # Check if .env file exists and load current values
    if [[ -f "$ENV_FILE" ]]; then
        env_exists=true
        log_info "Environment file exists: $ENV_FILE"
        
        # Load existing values
        if [[ -s "$ENV_FILE" ]]; then
            source "$ENV_FILE" 2>/dev/null || true
            current_bot_token="${TELEGRAM_BOT_TOKEN:-}"
            current_chat_id="${TELEGRAM_CHAT_ID:-}"
            
            # Check if configuration is complete
            if [[ -n "$current_bot_token" && -n "$current_chat_id" ]]; then
                config_complete=true
            fi
        fi
    fi

    # Show current configuration status
    echo
    log_info "Current notification configuration:"
    echo "  - Notifications in config: $current_notifications"
    echo "  - Environment file: $([ "$env_exists" == "true" ] && echo "exists" || echo "not found")"
    
    if [[ "$env_exists" == "true" ]]; then
        if [[ -n "$current_bot_token" ]]; then
            # Mask the token for security (show only first and last 4 characters)
            local masked_token="${current_bot_token:0:4}...${current_bot_token: -4}"
            echo "  - Bot token: $masked_token"
        else
            echo "  - Bot token: not configured"
        fi
        
        if [[ -n "$current_chat_id" ]]; then
            echo "  - Chat ID: $current_chat_id"
        else
            echo "  - Chat ID: not configured"
        fi
        
        echo "  - Configuration: $([ "$config_complete" == "true" ] && echo "complete" || echo "incomplete")"
    fi

    # Determine what to do based on current state
    if [[ "$current_notifications" == "true" && "$config_complete" == "true" ]]; then
        echo
        log_success "Telegram notifications are already fully configured"
        
        if ask_yes_no "Do you want to reconfigure Telegram notifications?"; then
            configure_telegram_settings
        else
            log_info "Keeping existing notification configuration"
            
            # Test the current configuration if user wants
            if ask_yes_no "Do you want to test the current notification configuration?"; then
                test_telegram_notification
            fi
        fi
        
    elif [[ "$current_notifications" == "true" && "$config_complete" == "false" ]]; then
        echo
        log_warning "Notifications are enabled but configuration is incomplete"
        
        if ask_yes_no "Do you want to complete the Telegram configuration?"; then
            configure_telegram_settings "$current_bot_token" "$current_chat_id"
        else
            log_warning "Notifications will not work properly without complete configuration"
            if ask_yes_no "Do you want to disable notifications?"; then
                yq eval '.notifications = false' -i "$CONFIG_FILE"
                log_info "Notifications disabled in configuration"
            fi
        fi
        
    elif [[ "$current_notifications" == "false" ]]; then
        echo
        if ask_yes_no "Do you want to enable Telegram notifications?"; then
            yq eval '.notifications = true' -i "$CONFIG_FILE"
            configure_telegram_settings "$current_bot_token" "$current_chat_id"
        else
            log_info "Notifications will remain disabled"
        fi
        
    else
        log_warning "Unknown notification state, reconfiguring..."
        configure_telegram_settings "$current_bot_token" "$current_chat_id"
    fi
}

# Helper function to configure Telegram settings
configure_telegram_settings() {
    local current_token="${1:-}"
    local current_chat_id="${2:-}"
    
    echo
    log_info "Configuring Telegram bot settings..."
    echo
    log_info "To get your Telegram bot token:"
    echo "  1. Message @BotFather on Telegram"
    echo "  2. Send /newbot and follow instructions"
    echo "  3. Copy the token provided"
    echo
    log_info "To get your Chat ID:"
    echo "  1. Send a message to your bot"
    echo "  2. Visit: https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates"
    echo "  3. Find 'chat':{'id': YOUR_CHAT_ID} in the response"
    echo

    local bot_token=""
    local chat_id=""

    # Get bot token
    if [[ -n "$current_token" ]]; then
        local masked_token="${current_token:0:4}...${current_token: -4}"
        read -p "Telegram bot token [current: $masked_token]: " bot_token
        bot_token=${bot_token:-$current_token}
    else
        while [[ -z "$bot_token" ]]; do
            read -p "Telegram bot token (required): " bot_token
            if [[ -z "$bot_token" ]]; then
                log_warning "Bot token is required for Telegram notifications"
            fi
        done
    fi

    # Get chat ID
    if [[ -n "$current_chat_id" ]]; then
        read -p "Telegram chat ID [current: $current_chat_id]: " chat_id
        chat_id=${chat_id:-$current_chat_id}
    else
        while [[ -z "$chat_id" ]]; do
            read -p "Telegram chat ID (required): " chat_id
            if [[ -z "$chat_id" ]]; then
                log_warning "Chat ID is required for Telegram notifications"
            fi
        done
    fi

    # Validate inputs
    if [[ -z "$bot_token" || -z "$chat_id" ]]; then
        log_error "Both bot token and chat ID are required"
        return 1
    fi

    # Create .env file
    log_info "Creating environment file..."
    cat >"$ENV_FILE" <<EOF
TELEGRAM_BOT_TOKEN=$bot_token
TELEGRAM_CHAT_ID=$chat_id
EOF

    chmod 600 "$ENV_FILE"
    log_success "Telegram configuration saved to $ENV_FILE"

    # Test the configuration
    if ask_yes_no "Do you want to test the Telegram notification?"; then
        test_telegram_notification "$bot_token" "$chat_id"
    fi
}

# Helper function to test Telegram notification
test_telegram_notification() {
    local test_token="${1:-}"
    local test_chat_id="${2:-}"
    
    # Use provided parameters or load from environment
    if [[ -z "$test_token" || -z "$test_chat_id" ]]; then
        if [[ -f "$ENV_FILE" ]]; then
            source "$ENV_FILE" 2>/dev/null || true
            test_token="${TELEGRAM_BOT_TOKEN:-}"
            test_chat_id="${TELEGRAM_CHAT_ID:-}"
        fi
    fi

    if [[ -z "$test_token" || -z "$test_chat_id" ]]; then
        log_error "Cannot test: missing bot token or chat ID"
        return 1
    fi

    log_info "Testing Telegram notification..."
    
    local test_message="🧪 *Test Notification*%0A%0AThis is a test message from BTRFS Backup script on $(hostname).%0A%0ATime: $(date)%0A%0AIf you receive this message, notifications are working correctly! ✅"
    local api_url="https://api.telegram.org/bot${test_token}/sendMessage"

    if curl -s -X POST "$api_url" \
        -d chat_id="$test_chat_id" \
        -d text="$test_message" \
        -d parse_mode="Markdown" >/dev/null; then
        log_success "Test notification sent successfully!"
        log_info "Check your Telegram to confirm you received the test message"
    else
        log_error "Failed to send test notification"
        log_warning "Please check your bot token and chat ID"
        
        if ask_yes_no "Do you want to reconfigure the Telegram settings?"; then
            configure_telegram_settings
        fi
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

    curl -Ls "$repo_url/btrfs-backup-debian-script.sh" -o "$INSTALL_DIR/$SCRIPT_NAME"
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
    cat >"/etc/logrotate.d/$SERVICE_NAME" <<EOF
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

    local service_file="/etc/systemd/system/$SERVICE_NAME.service"
    local timer_file="/etc/systemd/system/$SERVICE_NAME.timer"
    local service_exists=false
    local timer_exists=false
    local current_schedule=""

    # Check if service already exists
    if [[ -f "$service_file" ]]; then
        service_exists=true
        log_info "Service file already exists: $service_file"
    fi

    # Check if timer already exists and get current schedule
    if [[ -f "$timer_file" ]]; then
        timer_exists=true
        current_schedule=$(grep "OnCalendar=" "$timer_file" | cut -d'=' -f2 || echo "unknown")
        log_info "Timer file already exists: $timer_file"
        log_info "Current schedule: $current_schedule"
    fi

    # Show current status if both exist
    if [[ "$service_exists" == "true" && "$timer_exists" == "true" ]]; then
        echo
        log_info "Current systemd configuration:"
        echo "  - Service: $SERVICE_NAME.service (exists)"
        echo "  - Timer: $SERVICE_NAME.timer (exists)"
        echo "  - Schedule: $current_schedule"
        
        # Check if timer is enabled and running
        local timer_enabled="disabled"
        local timer_active="inactive"
        
        if systemctl is-enabled "$SERVICE_NAME.timer" &>/dev/null; then
            timer_enabled="enabled"
        fi
        
        if systemctl is-active "$SERVICE_NAME.timer" &>/dev/null; then
            timer_active="active"
        fi
        
        echo "  - Status: $timer_enabled, $timer_active"
        echo

        if ! ask_yes_no "Do you want to reconfigure the systemd service and timer?"; then
            log_info "Keeping existing systemd configuration"
            
            # Ensure timer is enabled and started if not already
            if [[ "$timer_enabled" == "disabled" ]]; then
                log_info "Enabling timer..."
                systemctl enable "$SERVICE_NAME.timer"
            fi
            
            if [[ "$timer_active" == "inactive" ]]; then
                log_info "Starting timer..."
                systemctl start "$SERVICE_NAME.timer"
            fi
            
            log_success "Systemd configuration verified"
            return 0
        fi
        
        # Stop timer before reconfiguration
        log_info "Stopping existing timer for reconfiguration..."
        systemctl stop "$SERVICE_NAME.timer" 2>/dev/null || true
    fi

    # Create or update service file
    log_info "Creating/updating service file..."
    cat >"$service_file" <<EOF
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

    if [[ "$service_exists" == "true" ]]; then
        log_success "Service file updated"
    else
        log_success "Service file created"
    fi

    # Configure schedule
    echo
    log_info "Configuring backup schedule..."
    echo "Cron expression examples:"
    echo "  *-*-* 04:00:00    - Every day at 4:00 AM"
    echo "  *-*-* 02:30:00    - Every day at 2:30 AM"
    echo "  Sun *-*-* 03:00:00 - Every Sunday at 3:00 AM"
    echo "  Mon,Wed,Fri *-*-* 06:00:00 - Monday, Wednesday, Friday at 6:00 AM"
    echo

    local default_schedule="*-*-* 04:00:00"
    if [[ -n "$current_schedule" && "$current_schedule" != "unknown" ]]; then
        default_schedule="$current_schedule"
        echo "Current schedule: $current_schedule"
    fi

    local cron_expression
    read -p "Time expression for backup [$default_schedule]: " cron_expression
    cron_expression=${cron_expression:-"$default_schedule"}

    # Validate cron expression format (basic validation)
    if [[ ! "$cron_expression" =~ ^[*0-9,-]+[[:space:]]+[*0-9:-]+$ ]]; then
        log_warning "Cron expression format might be invalid: $cron_expression"
        if ! ask_yes_no "Continue anyway?"; then
            log_info "Using default schedule: $default_schedule"
            cron_expression="$default_schedule"
        fi
    fi

    # Create or update timer file
    log_info "Creating/updating timer file..."
    cat >"$timer_file" <<EOF
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

    if [[ "$timer_exists" == "true" ]]; then
        log_success "Timer file updated"
    else
        log_success "Timer file created"
    fi

    # Reload systemd daemon
    log_info "Reloading systemd daemon..."
    systemctl daemon-reload

    # Enable and start timer
    log_info "Enabling and starting timer..."
    systemctl enable "$SERVICE_NAME.timer"
    systemctl start "$SERVICE_NAME.timer"

    # Verify timer status
    if systemctl is-active "$SERVICE_NAME.timer" &>/dev/null; then
        log_success "Timer is active and running"
    else
        log_warning "Timer might not be running properly"
    fi

    if systemctl is-enabled "$SERVICE_NAME.timer" &>/dev/null; then
        log_success "Timer is enabled for automatic start"
    else
        log_warning "Timer is not enabled"
    fi

    # Show timer information
    echo
    log_success "Service and timer configured successfully"
    log_info "Configuration details:"
    echo "  - Service file: $service_file"
    echo "  - Timer file: $timer_file"
    echo "  - Schedule: $cron_expression"
    echo "  - Status: enabled and active"
    
    # Show next scheduled run
    local next_run=$(systemctl list-timers "$SERVICE_NAME.timer" --no-legend 2>/dev/null | awk '{print $1, $2}' || echo "unknown")
    if [[ "$next_run" != "unknown" && -n "$next_run" ]]; then
        echo "  - Next run: $next_run"
    fi

    echo
    log_info "Useful commands:"
    echo "  - Check timer status: systemctl status $SERVICE_NAME.timer"
    echo "  - View next scheduled runs: systemctl list-timers $SERVICE_NAME.timer"
    echo "  - Stop timer: systemctl stop $SERVICE_NAME.timer"
    echo "  - Start timer: systemctl start $SERVICE_NAME.timer"
    echo "  - Disable timer: systemctl disable $SERVICE_NAME.timer"
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

    for ((i = 0; i < parts_count; i++)); do
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

    # Step 6: Configure infrastructure
    configure_postgresql_infrastructure
    configure_nginx_infrastructure
    configure_redis_infrastructure
    configure_meilisearch_infrastructure

    # Step 7: Configure services
    configure_services

    # Step 8: Configure path backups
    configure_paths

    # Step 9: Configure /etc backup
    configure_etc

    # Step 10: Configure notifications
    configure_notifications

    # Step 11: Display final configuration
    display_config

    # Step 12: Download scripts
    download_scripts

    # Step 13: Configure logging
    configure_logging

    # Step 14: Create systemd service and timer
    create_systemd_service

    # Step 15: Run initial backup
    run_initial_backup

    # Step 16: Unmount disks
    unmount_disks

    # Show final status
    show_final_status
}

# Run main function
main "$@"
