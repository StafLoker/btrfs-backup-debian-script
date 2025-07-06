<div align="center">
   <h1><b>BTRFS Backup Debian Script</b></h1>
   <p><i>~ Still online ~</i></p>
   <p align="center">
       · <a href="https://github.com/StafLoker/btrfs-backup-debian-script/releases">Releases</a> ·
   </p>
</div>

<div align="center">
   <a href="https://github.com/StafLoker/btrfs-backup-debian-script/releases"><img src="https://img.shields.io/github/downloads/StafLoker/btrfs-backup-debian-script/total.svg?style=flat" alt="downloads"/></a>
   <a href="https://github.com/StafLoker/btrfs-backup-debian-script/releases"><img src="https://img.shields.io/github/release-pre/StafLoker/btrfs-backup-debian-script.svg?style=flat" alt="latest version"/></a>
   <a href="https://github.com/StafLoker/btrfs-backup-debian-script/blob/main/LICENSE"><img src="https://img.shields.io/github/license/StafLoker/btrfs-backup-debian-script.svg?style=flat" alt="license"/></a>

   <p>A comprehensive backup solution for Debian-based systems using BTRFS snapshots. This script provides automated backups of PostgreSQL databases, system configurations, application data, SSL certificates, and Docker configurations with intelligent retention policies.</p>
</div>

## **Features**

- 🔄 **Automated BTRFS Snapshots** - Daily, weekly, and monthly snapshots with configurable retention
- 🗃️ **PostgreSQL Backup** - Complete database dumps including globals and individual databases
- ⚙️ **System Configuration Backup** - Backs up `/etc` while excluding sensitive files
- 📁 **Custom Path Backup** - Configurable paths with optional service management
- 🔒 **SSL Certificate Backup** - Let's Encrypt, custom SSL certificates, and private keys
- 🐳 **Docker Configuration Backup** - Docker daemon configs and docker-compose files
- 📱 **Telegram Notifications** - Real-time backup status and error notifications
- 🔧 **Service Management** - Automatic stop/start of services during backup
- 📊 **Retention Policies** - Configurable cleanup of old snapshots
- 🚀 **Easy Installation** - One-command setup with interactive configuration

## **Requirements**

- Debian-based Linux distribution (Debian, Ubuntu, etc.)
- Root access (sudo)
- BTRFS-formatted backup drives
- Internet connection for installation

### **Dependencies** (automatically installed)
- `curl` - For downloading and API calls
- `sed` - Text processing
- `yq` - YAML processing
- `btrfs-progs` - BTRFS utilities
- `rsync` - File synchronization
- `postgresql-client` (if PostgreSQL backup enabled)

## **Install & Upgrade**

### **Quick Installation**
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/StafLoker/btrfs-backup-debian-script/main/install.sh)"
```

### **Manual Installation**
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
3. **Backup Configuration** - Selection of what to backup (PostgreSQL, paths, certificates, etc.)
4. **Retention Policy** - Configuration of snapshot retention periods
5. **Notifications Setup** - Optional Telegram bot configuration
6. **Service Creation** - Systemd service and timer setup

## **Configuration**

### **Main Configuration File**
Location: `/etc/btrfs-backup/config.yaml`

```yaml
parts:
  - label: backup_1
    path: /mnt/backups/disk_1
    dev: /dev/sdc1
  - label: backup_2
    path: /mnt/backups/disk_2
    dev: /dev/sdd1

policy:
  daily_retention: 7      # Keep 7 daily snapshots
  weekly_retention: 4     # Keep 4 weekly snapshots
  monthly_retention: 12   # Keep 12 monthly snapshots

backups:
  postgresql: true
  paths:
    - path: /home/user/photos
    - label: service_1
      systemd: service_1
      path: /var/lib/service_1
    - label: service_2
      systemd: service_2
      path: /var/lib/service_2
  etc: true
  docker: true
  certificates: true

notifications: true
```

### **Environment Variables**
Location: `/etc/btrfs-backup/.env`

```bash
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_CHAT_ID=your_chat_id_here
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
    ├── data/                    # Current backup data (BTRFS subvolume)
    │   ├── postgresql/         # Database dumps
    │   ├── etc/               # System configurations
    │   ├── paths/             # Custom paths
    │   ├── certificates/      # SSL certificates
    │   └── docker/            # Docker configurations
    └── snapshots/             # Historical snapshots
        ├── daily/             # Daily snapshots
        ├── weekly/            # Weekly snapshots (Sundays)
        └── monthly/           # Monthly snapshots (1st of month)
```

## **Telegram Notifications**

To enable Telegram notifications:

1. **Create a Telegram Bot**:
   - Message @BotFather on Telegram
   - Send `/newbot` and follow instructions
   - Save the bot token

2. **Get Your Chat ID**:
   - Send a message to your bot
   - Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
   - Find your chat ID in the response

3. **Configure During Installation** or manually edit `/etc/btrfs-backup/.env`

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

### **Database Recovery**
```bash
# Restore PostgreSQL database
sudo -u postgres psql < /mnt/backups/disk_1/hostname/data/postgresql/database_name_20250101_040000.sql
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

**Backup fails to mount disks**:
```bash
# Check disk availability
lsblk

# Check fstab entries
cat /etc/fstab

# Test manual mount
sudo mount /dev/sdc1 /mnt/backups/disk_1
```

**Permission errors**:
```bash
# Ensure correct permissions
sudo chown root:root /etc/btrfs-backup/.env
sudo chmod 600 /etc/btrfs-backup/.env
```

**PostgreSQL backup fails**:
```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Test database connection
sudo -u postgres psql -l
```

### **Log Analysis**
```bash
# Check for errors in logs
sudo grep -i error /var/log/backup_$(hostname).log

# View systemd service errors
sudo journalctl -u backup-$(hostname).service --since yesterday
```

## **Customization**

### **Adding Custom Backup Paths**
Edit `/etc/btrfs-backup/config.yaml`:

```yaml
backups:
  paths:
    - path: /opt/myapp
      label: myapp
      systemd: myapp.service  # Optional: stop service during backup
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
```

### **Custom Retention Policies**
Edit `/etc/btrfs-backup/config.yaml`:

```yaml
policy:
  daily_retention: 14     # Keep 14 days
  weekly_retention: 8     # Keep 8 weeks
  monthly_retention: 24   # Keep 24 months
```

## **Security Notes**

- **Environment File**: Ensure the `.env` file is not accessible to other users on the system. Use `chmod 600` to restrict permissions.
- **Backup Encryption**: Consider encrypting backup drives for additional security
- **Network Security**: If using network-attached storage, ensure secure connection
- **Access Control**: Regularly review who has access to backup systems
- **Key Rotation**: Periodically rotate Telegram bot tokens and other credentials

## **Performance Optimization**

### **Large Datasets**
- Use multiple backup drives for parallel writes
- Consider excluding cache directories and temporary files
- Schedule backups during low-usage periods

### **Network Backups**
- Use compression for network transfers
- Implement bandwidth throttling if needed
- Consider incremental network sync tools

## **Contributing**

Contributions are welcome! Please feel free to submit issues, feature requests, or pull requests.

### **Development Setup**
```bash
# Clone the repository
git clone https://github.com/StafLoker/btrfs-backup-debian-script.git

# Make changes and test locally
chmod +x install.sh backup.sh

# Test installation
sudo ./install.sh
```

## **Support**

- **Issues**: [GitHub Issues](https://github.com/StafLoker/btrfs-backup-debian-script/issues)
- **Documentation**: This README and inline script comments
- **Community**: Feel free to fork and adapt for your needs

## **License**

This project is released under the MIT License. See the [LICENSE](LICENSE) file for more details.

---

**⚠️ Important**: Always test your backup and recovery procedures in a safe environment before relying on them for production systems.