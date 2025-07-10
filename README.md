<div align="center">
   <h1><b>BTRFS Backup Debian Script</b></h1>
   <p><i>~ Sleep quietly ~</i></p>
   <p align="center">
       · <a href="https://github.com/StafLoker/btrfs-backup-debian-script/releases">Releases</a> ·
   </p>
</div>

<div align="center">
   <a href="https://github.com/StafLoker/btrfs-backup-debian-script/releases"><img src="https://img.shields.io/github/downloads/StafLoker/btrfs-backup-debian-script/total.svg?style=flat" alt="downloads"/></a>
   <a href="https://github.com/StafLoker/btrfs-backup-debian-script/releases"><img src="https://img.shields.io/github/release-pre/StafLoker/btrfs-backup-debian-script.svg?style=flat" alt="latest version"/></a>
   <a href="https://github.com/StafLoker/btrfs-backup-debian-script/blob/main/LICENSE"><img src="https://img.shields.io/github/license/StafLoker/btrfs-backup-debian-script.svg?style=flat" alt="license"/></a>

   <p>A comprehensive backup solution for Debian-based systems using BTRFS snapshots. This script provides automated backups of PostgreSQL databases, system configurations, application data, SSL certificates, service configurations, and enhanced support for both system and user services including Podman containers.</p>
</div>

## **Install & Upgrade**

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/StafLoker/btrfs-backup-debian-script/main/install.sh)"
```

## **Features**

- 🔄 **Automated BTRFS Snapshots** - Daily, weekly, and monthly snapshots with configurable retention
- 🗃️ **PostgreSQL Infrastructure Backup** - Complete database dumps including globals and individual databases
- 🌐 **Nginx Infrastructure Backup** - Configuration and SSL certificates management
- 🔴 **Redis Infrastructure Backup** - Configuration backup with duplication avoidance
- 🔍 **Meilisearch Infrastructure Backup** - Configuration and data backup
- ⚙️ **Enhanced Service Management** - Support for both system and user services (Podman containers)
- 🐳 **Container Support** - Docker/Podman Compose backup with enhanced configuration
- 📁 **Custom Path Backup** - Configurable paths with optional labels
- 🔒 **System Configuration Backup** - Backs up `/etc` while excluding sensitive files and avoiding duplicates
- 📱 **Telegram Notifications** - Real-time backup status and error notifications with disk usage info
- 🛠️ **Intelligent Service Management** - Stop/start services during backup including user services
- 📊 **Intelligent Retention Policies** - Configurable cleanup of old snapshots
- 🚀 **Easy Installation** - One-command setup with interactive configuration

## **Requirements**

- Debian-based Linux distribution (Debian, Ubuntu, etc.)
- Root access (sudo)
- BTRFS-formatted backup drives
- Internet connection for installation

### **Dependencies** (automatically installed)

- `curl` - For downloading and API calls
- `wget` - For file downloads
- `sed` - Text processing
- `tar` - Archive handling
- `yq` - YAML processing (mikefarah/yq v4.45.4)
- `btrfs-progs` - BTRFS utilities
- `rsync` - File synchronization
- `postgresql-client` (optional, for PostgreSQL backups)

## **Manual Installation**

```bash
# Download the installer
wget https://raw.githubusercontent.com/StafLoker/btrfs-backup-debian-script/main/install.sh

# Make it executable
chmod +x install.sh

# Run as root
sudo ./install.sh
```

The installer will guide you through:

1. **Dependency Installation** - Automatic detection and installation of required packages
2. **Disk Configuration** - Setup of backup drives and mount points
3. **Retention Policy Configuration** - Configuration of snapshot retention periods
4. **Infrastructure Backup Configuration** - PostgreSQL, Nginx, Redis, and Meilisearch backup settings
5. **Enhanced Service Backup Configuration** - System and user service backup settings (Docker/Podman Compose, data, configs, logs)
6. **Path Backup Configuration** - Custom directories to backup
7. **System Configuration** - /etc directory backup settings
8. **Notifications Setup** - Optional Telegram bot configuration
9. **Service Creation** - Systemd service and timer setup

## **Configuration**

### **Main Configuration File**

Location: `/etc/btrfs-backup/config.yaml`

```yaml
# At least one backup disk is required
parts:
  - label: backup_1
    dev: /dev/sdc1
    path: /mnt/backups/disk_1
  - label: backup_2
    dev: /dev/sdd1
    path: /mnt/backups/disk_2

# Enable/disable Telegram notifications
notifications: true

# Snapshot retention policies
policy:
  daily_retention: 7 # Keep 7 daily snapshots
  weekly_retention: 4 # Keep 4 weekly snapshots (created on Sundays)
  monthly_retention: 12 # Keep 12 monthly snapshots (created on 1st of month)

backups:
  # Infrastructure services backup
  infrastructure:
    postgresql:
      global: true # Backup global configurations (roles, users)
      all_db: true # Backup all databases
      config: true # Backup /etc/postgresql (skipped if etc: true)
    nginx:
      config: true # Backup /etc/nginx (skipped if etc: true)
      certificates: true # Backup SSL certificates from sites-available
    redis:
      config: true # Backup /etc/redis (skipped if etc: true)
    meilisearch:
      config: true # Backup /etc/meilisearch (skipped if etc: true)
      data: true # Backup /var/lib/meilisearch

  # Individual services backup (Enhanced format)
  services:
    # System service example (runs as root)
    - label: gitea # Mandatory: Service identifier
      systemd: # Enhanced systemd configuration
        name: gitea # Mandatory: Systemd service name
      containers: # Container configuration (replaces docker_compsose)
        compose: /opt/gitea # Optional: Container compose directory
      config: /etc/gitea # Optional: Configuration directory
      data:
        files: /var/lib/gitea # Optional: Data files directory
        pg-db: giteadb # Optional: PostgreSQL database name
      logs: /var/log/gitea # Optional: Logs directory

    # User service example (Podman containers running as user)
    - label: linkwarden
      systemd:
        name: podman-compose@linkwarden # User service name
        podman: # Podman user configuration
          user: admin # User name running the service
          uid: 1000 # User ID
      containers:
        compose: /opt/linkwarden
      data:
        files: /var/lib/linkwarden
        pg-db: linkwardendb

    # User service with multiple containers
    - label: authentik
      systemd:
        name: podman-compose@authentik
        podman:
          user: admin
          uid: 1000
      containers:
        compose: /opt/authentik
      data:
        files: /var/lib/authentik
        pg-db: authentik

    # System service without containers
    - label: opencloud
      systemd:
        name: opencloud
      config: /etc/opencloud
      data:
        files: /var/lib/opencloud

  # Custom paths backup
  paths:
    - label: user_photos # Mandatory: Path identifier
      path: /home/user/photos # Mandatory: Directory to backup
    - label: documents
      path: /srv/documents

  # System configuration backup
  etc: true # Backup /etc directory (excludes sensitive files and duplicates from infrastructure/services)
```

### **Environment Variables**

Location: `/etc/btrfs-backup/.env`

```bash
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_CHAT_ID=your_chat_id_here
```

## **Enhanced Service Management**

### **System Services vs User Services**

**System Services** (run as root):

- Traditional systemd services
- Services installed system-wide
- Examples: nginx, postgresql, custom applications

**User Services** (run as specific user):

- Podman containers managed by systemctl --user
- Services running in user session
- Examples: podman-compose@linkwarden, podman-compose@authentik

### **Service Types Configuration**

#### **System Service Example**

```yaml
- label: gitea
  systemd:
    name: gitea
  containers:
    compose: /opt/gitea
  config: /etc/gitea
  data:
    files: /var/lib/gitea
    pg-db: giteadb
```

#### **User Service Example (Podman)**

```yaml
- label: linkwarden
  systemd:
    name: podman-compose@linkwarden
    podman:
      user: admin # User running the service
      uid: 1000 # User ID for proper permission handling
  containers:
    compose: /opt/linkwarden
  data:
    files: /var/lib/linkwarden
    pg-db: linkwardendb
```

### **Service Detection During Installation**

The installer can automatically detect running user services:

```bash
# For user 'admin', it will show:
Available user services:
  - podman-compose@authentik.service
  - podman-compose@linkwarden.service
  - podman-compose@remnawave.service
```

## **Usage**

### **Automatic Backups**

The installer creates a systemd timer that runs backups automatically. By default, backups run daily at 4:00 AM.

```bash
# Check timer status
sudo systemctl status backup-$(hostname).timer

# View timer schedule
sudo systemctl list-timers backup-$(hostname).timer
```

### **Manual Backup**

```bash
# Run backup manually
sudo /usr/local/bin/backup-$(hostname).sh

# Or use the systemd service
sudo systemctl start backup-$(hostname).service
```

### **View Logs**

```bash
# View real-time logs
sudo tail -f /var/log/backup_$(hostname).log

# View systemd service logs
sudo journalctl -u backup-$(hostname).service -f
```

## **Backup Structure**

Each backup disk will have the following structure:

```
/mnt/backups/disk_1/
└── hostname/
    ├── data/                           # Current backup data (BTRFS subvolume)
    │   ├── infrastructure/             # Infrastructure backups
    │   │   ├── postgresql/            # PostgreSQL dumps and config
    │   │   │   ├── globals_timestamp.sql
    │   │   │   ├── database_timestamp.sql
    │   │   │   └── config/            # PostgreSQL configuration
    │   │   ├── nginx/                 # Nginx configuration and certificates
    │   │   │   ├── config/            # Nginx configuration files
    │   │   │   └── certificates/      # SSL certificates by site
    │   │   ├── redis/                 # Redis configuration
    │   │   │   └── config/            # Redis configuration files
    │   │   └── meilisearch/           # Meilisearch configuration and data
    │   │       ├── config/            # Meilisearch configuration
    │   │       └── data/              # Meilisearch data files
    │   ├── services/                   # Individual services
    │   │   ├── gitea/                 # Service-specific backups
    │   │   │   ├── containers_compose/ # Container compose files (renamed from docker_compose)
    │   │   │   ├── config/            # Service configuration
    │   │   │   ├── data_files/        # Service data files
    │   │   │   ├── database/          # Service database dumps
    │   │   │   └── logs/              # Service logs
    │   │   ├── linkwarden/            # User service backup
    │   │   │   ├── containers_compose/ # Podman compose files
    │   │   │   ├── data_files/        # Service data files
    │   │   │   └── database/          # Service database dumps
    │   │   └── authentik/             # Another user service
    │   ├── paths/                      # Custom paths
    │   │   ├── user_photos/           # Labeled custom directories
    │   │   └── documents/
    │   └── etc/                       # System configuration
    └── snapshots/                     # Historical snapshots
        ├── daily/                     # Daily snapshots
        ├── weekly/                    # Weekly snapshots (Sundays)
        └── monthly/                   # Monthly snapshots (1st of month)
```

## **Service Backup Details**

### **Enhanced Container Backup**

When `containers.compose` is specified, the script backs up:

- `docker-compose.yml` and `docker-compose.yaml` files
- All `.env*` files
- `Dockerfile`, `.dockerignore`
- `docker-compose.override.yml/yaml` files

### **Service Management**

- **System services**: Stopped/started using `systemctl`
- **User services**: Stopped/started using `systemctl --user` as the specified user
- **Service isolation**: Each service runs in proper user context
- **Error handling**: Failed service operations are logged but don't stop backup

### **User Service Execution**

For user services, the script uses `runuser` to ensure proper execution context:

```bash
# Example: Stop user service
runuser -l admin -c "systemctl --user stop 'podman-compose@linkwarden'"

# Example: Start user service
runuser -l admin -c "systemctl --user start 'podman-compose@linkwarden'"
```

### **Database Backup**

- PostgreSQL databases specified in `pg-db` are dumped individually
- Global PostgreSQL backup includes roles and users
- All database backups include timestamp in filename

### **Intelligent Duplication Avoidance**

- If `etc: true` is enabled, service configs under `/etc/` are skipped
- Infrastructure configs are skipped if covered by `/etc` backup
- Prevents duplicate backups and saves storage space

## **Telegram Notifications**

### **Setup Instructions**

1. **Create a Telegram Bot**:

   - Message @BotFather on Telegram
   - Send `/newbot` and follow instructions
   - Save the bot token

2. **Get Your Chat ID**:

   - Send a message to your bot
   - Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
   - Find your chat ID in the response

3. **Configure During Installation** or manually edit `/etc/btrfs-backup/.env`

### **Notification Features**

- **Success/Failure Status** with appropriate icons
- **Backup Duration** timing information
- **Disk Usage Information** for each backup disk
- **Error Details** when backups fail
- **Real-time Error Notifications** during backup process

## **Management Commands**

### **Timer Management**

```bash
# Enable/disable automatic backups
sudo systemctl enable backup-$(hostname).timer   # Enable
sudo systemctl disable backup-$(hostname).timer  # Disable

# Start/stop timer
sudo systemctl start backup-$(hostname).timer    # Start
sudo systemctl stop backup-$(hostname).timer     # Stop
```

### **Configuration Management**

```bash
# Edit main configuration
sudo nano /etc/btrfs-backup/config.yaml

# Edit environment variables
sudo nano /etc/btrfs-backup/.env

# Reload systemd after changes
sudo systemctl daemon-reload
```

### **User Service Management**

```bash
# Check user services (as the user)
systemctl --user list-units --type=service

# Check specific user service status
sudo runuser -l admin -c "systemctl --user status podman-compose@linkwarden"

# Manually stop/start user service
sudo runuser -l admin -c "systemctl --user stop podman-compose@linkwarden"
sudo runuser -l admin -c "systemctl --user start podman-compose@linkwarden"
```

### **Snapshot Management**

```bash
# List snapshots on a backup disk
sudo btrfs subvolume list /mnt/backups/disk_1

# Manually delete a snapshot
sudo btrfs subvolume delete /mnt/backups/disk_1/hostname/snapshots/daily/20250101_040000
```

## **Recovery**

### **File Recovery**

```bash
# Browse snapshots
ls /mnt/backups/disk_1/hostname/snapshots/daily/

# Copy files from a snapshot
sudo cp -r /mnt/backups/disk_1/hostname/snapshots/daily/20250101_040000/etc/nginx/ /etc/nginx/
```

### **Service Recovery**

#### **System Service Recovery**

```bash
# Restore service data
sudo rsync -av /mnt/backups/disk_1/hostname/data/services/gitea/data_files/ /var/lib/gitea/

# Restore service configuration
sudo rsync -av /mnt/backups/disk_1/hostname/data/services/gitea/config/ /etc/gitea/
```

#### **User Service Recovery**

```bash
# Restore user service data (as root, then fix permissions)
sudo rsync -av /mnt/backups/disk_1/hostname/data/services/linkwarden/data_files/ /var/lib/linkwarden/
sudo chown -R admin:admin /var/lib/linkwarden/

# Restore container compose files
sudo rsync -av /mnt/backups/disk_1/hostname/data/services/linkwarden/containers_compose/ /opt/linkwarden/
sudo chown -R admin:admin /opt/linkwarden/
```

### **Database Recovery**

```bash
# Restore PostgreSQL database
sudo -u postgres psql < /mnt/backups/disk_1/hostname/data/infrastructure/postgresql/database_name_20250101_040000.sql

# Restore service database
sudo -u postgres psql < /mnt/backups/disk_1/hostname/data/services/gitea/database/giteadb_20250101_040000.sql
```

### **Complete System Recovery**

```bash
# Mount backup disk
sudo mount /dev/sdc1 /mnt/recovery

# Restore from specific snapshot
sudo rsync -av /mnt/recovery/hostname/snapshots/daily/20250101_040000/etc/ /etc/
```

## **Troubleshooting**

### **Common Issues**

**User service fails to stop/start**:

```bash
# Check if user has systemd session
sudo runuser -l admin -c "systemctl --user status"

# Check specific service status
sudo runuser -l admin -c "systemctl --user status podman-compose@linkwarden"

# Check user service logs
sudo runuser -l admin -c "journalctl --user -u podman-compose@linkwarden"
```

**Permission errors with user services**:

```bash
# Ensure user owns service directories
sudo chown -R admin:admin /opt/linkwarden/
sudo chown -R admin:admin /var/lib/linkwarden/

# Check user ID matches configuration
id admin
```

**Backup fails to mount disks**:

```bash
# Check disk availability
lsblk

# Check fstab entries
cat /etc/fstab

# Test manual mount
sudo mount /dev/sdc1 /mnt/backups/disk_1
```

**PostgreSQL backup fails**:

```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Test database connection
sudo -u postgres psql -l

# Install PostgreSQL client if missing
sudo apt-get install postgresql-client
```

### **Log Analysis**

```bash
# Check for errors in logs
sudo grep -i error /var/log/backup_$(hostname).log

# View systemd service errors
sudo journalctl -u backup-$(hostname).service --since yesterday

# Check BTRFS filesystem health
sudo btrfs filesystem show
sudo btrfs scrub status /mnt/backups/disk_1
```

## **Customization**

### **Adding New System Services**

Edit `/etc/btrfs-backup/config.yaml`:

```yaml
backups:
  services:
    - label: myservice
      systemd:
        name: myservice
      containers: # Optional
        compose: /opt/myservice
      config: /etc/myservice # Optional
      data:
        files: /var/lib/myservice # Optional
        pg-db: myservicedb # Optional
      logs: /var/log/myservice # Optional
```

### **Adding New User Services**

```yaml
backups:
  services:
    - label: myapp
      systemd:
        name: podman-compose@myapp
        podman:
          user: admin
          uid: 1000
      containers:
        compose: /opt/myapp
      data:
        files: /var/lib/myapp
        pg-db: myappdb
```

### **Adding Infrastructure Services**

```yaml
backups:
  infrastructure:
    redis:
      config: true # Backup /etc/redis
    meilisearch:
      config: true # Backup /etc/meilisearch
      data: true # Backup /var/lib/meilisearch
```

### **Adding Custom Backup Paths**

```yaml
backups:
  paths:
    - label: mydata
      path: /opt/mydata
```

### **Changing Backup Schedule**

Edit the systemd timer:

```bash
sudo systemctl edit backup-$(hostname).timer
```

Add custom schedule:

```ini
[Timer]
OnCalendar=*-*-* 02:00:00  # 2:00 AM daily
OnCalendar=Sun *-*-* 03:00:00  # 3:00 AM on Sundays only
```

### **Custom Retention Policies**

Edit `/etc/btrfs-backup/config.yaml`:

```yaml
policy:
  daily_retention: 14 # Keep 14 days
  weekly_retention: 8 # Keep 8 weeks
  monthly_retention: 24 # Keep 24 months
```

## **Security Notes**

- **Environment File**: Ensure the `.env` file is not accessible to other users on the system. Use `chmod 600` to restrict permissions.
- **User Service Security**: User services run with user permissions, providing better isolation
- **Backup Encryption**: Consider encrypting backup drives for additional security
- **Network Security**: If using network-attached storage, ensure secure connection
- **Access Control**: Regularly review who has access to backup systems
- **Key Rotation**: Periodically rotate Telegram bot tokens and other credentials
- **Database Security**: PostgreSQL backups may contain sensitive data - secure backup locations appropriately

## **License**

This project is released under the MIT License. See the [LICENSE](LICENSE) file for more details.
