#!/bin/bash

# system_cleanup.sh - System cleanup and maintenance script
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/system_cleanup.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Default values if not set in config
: ${LOG_DIR:="./logs"}
: ${TEMP_DIRS:="/tmp /var/tmp"}
: ${LOG_AGE:=30}
: ${BACKUP_BEFORE_CLEAN:=true}

# Logging setup
LOG_FILE="$LOG_DIR/system_cleanup_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if running as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        log "Error: This script must be run as root"
        exit 1
    fi
}

# Function to backup before cleaning
backup_directory() {
    local dir="$1"
    local backup_name
    backup_name="$(basename "$dir")_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    if [ "$BACKUP_BEFORE_CLEAN" = true ]; then
        log "Creating backup of $dir..."
        if tar -czf "/root/cleanup_backups/$backup_name" -C "$dir" .; then
            log "Backup created: /root/cleanup_backups/$backup_name"
            return 0
        else
            log "Failed to create backup of $dir"
            return 1
        fi
    fi
}

# Function to clean package cache
clean_package_cache() {
    log "Cleaning package cache..."
    
    if [ -f /etc/debian_version ]; then
        # Clean apt cache
        apt-get clean
        apt-get autoclean
        apt-get autoremove -y
        
        # Remove old kernels
        if [ "$REMOVE_OLD_KERNELS" = true ]; then
            log "Removing old kernels..."
            dpkg -l 'linux-*' | sed '/^ii/!d;/'"$(uname -r | sed "s/\(.*\)-\([^0-9]\+\)/\1/")"'/d;s/^[^ ]* [^ ]* \([^ ]*\).*/\1/;/[0-9]/!d' | xargs apt-get -y purge
        fi
    elif [ -f /etc/redhat-release ]; then
        # Clean yum cache
        yum clean all
        
        # Remove old kernels
        if [ "$REMOVE_OLD_KERNELS" = true ]; then
            log "Removing old kernels..."
            package-cleanup --oldkernels --count=1
        fi
    fi
}

# Function to clean user cache
clean_user_cache() {
    log "Cleaning user cache..."
    
    find /home -type f -name ".bash_history" -delete
    find /home -type f -name ".viminfo" -delete
    
    if [ "$CLEAN_BROWSER_DATA" = true ]; then
        for user_home in /home/*; do
            user=$(basename "$user_home")
            
            # Chrome
            rm -rf "$user_home/.cache/google-chrome/Default/Cache"/*
            
            # Firefox
            rm -rf "$user_home/.cache/mozilla/firefox/*.default/Cache"/*
            
            log "Cleaned browser cache for user: $user"
        done
    fi
}

# Function to clean temporary files
clean_temp_files() {
    log "Cleaning temporary files..."
    
    for dir in $TEMP_DIRS; do
        if [ -d "$dir" ]; then
            if backup_directory "$dir"; then
                find "$dir" -type f -atime +1 -delete
                find "$dir" -type d -empty -delete
                log "Cleaned temporary files in $dir"
            fi
        fi
    done
}

# Function to clean log files
clean_logs() {
    log "Cleaning old log files..."
    
    # Clean system logs
    if [ "$CLEAN_SYSTEM_LOGS" = true ]; then
        find /var/log -type f -name "*.log" -mtime +"$LOG_AGE" -delete
        find /var/log -type f -name "*.log.*" -mtime +"$LOG_AGE" -delete
        
        # Rotate logs
        if command -v logrotate &>/dev/null; then
            logrotate -f /etc/logrotate.conf
        fi
    fi
    
    # Clean application-specific logs
    if [ -n "$APP_LOG_DIRS" ]; then
        for dir in $APP_LOG_DIRS; do
            if [ -d "$dir" ]; then
                find "$dir" -type f -name "*.log" -mtime +"$LOG_AGE" -delete
                log "Cleaned logs in $dir"
            fi
        done
    fi
}

# Function to clean Docker
clean_docker() {
    if [ "$CLEAN_DOCKER" = true ] && command -v docker &>/dev/null; then
        log "Cleaning Docker..."
        
        # Remove unused containers
        docker container prune -f
        
        # Remove unused images
        docker image prune -a -f
        
        # Remove unused volumes
        docker volume prune -f
        
        # Remove unused networks
        docker network prune -f
    fi
}

# Function to clean thumbnails
clean_thumbnails() {
    log "Cleaning thumbnails..."
    
    for user_home in /home/*; do
        if [ -d "$user_home/.cache/thumbnails" ]; then
            rm -rf "$user_home/.cache/thumbnails"/*
            log "Cleaned thumbnails for user: $(basename "$user_home")"
        fi
    done
}

# Function to clean mail queue
clean_mail_queue() {
    if [ "$CLEAN_MAIL_QUEUE" = true ]; then
        log "Cleaning mail queue..."
        
        if command -v postsuper &>/dev/null; then
            postsuper -d ALL
            log "Cleaned Postfix mail queue"
        fi
    fi
}

# Function to clean session files
clean_sessions() {
    log "Cleaning session files..."
    
    if [ -d /var/lib/php/sessions ]; then
        find /var/lib/php/sessions -type f -mtime +"$SESSION_AGE" -delete
        log "Cleaned PHP session files"
    fi
    
    if [ -d /tmp/sessions ]; then
        find /tmp/sessions -type f -mtime +"$SESSION_AGE" -delete
        log "Cleaned temporary session files"
    fi
}

# Function to clean trash
clean_trash() {
    log "Cleaning trash..."
    
    for user_home in /home/*; do
        if [ -d "$user_home/.local/share/Trash" ]; then
            rm -rf "$user_home/.local/share/Trash"/*
            log "Cleaned trash for user: $(basename "$user_home")"
        fi
    done
}

# Function to clean systemd journal
clean_journal() {
    if [ "$CLEAN_JOURNAL" = true ]; then
        log "Cleaning systemd journal..."
        
        if command -v journalctl &>/dev/null; then
            journalctl --vacuum-time="${JOURNAL_RETAIN_DAYS}days"
            log "Cleaned journal older than $JOURNAL_RETAIN_DAYS days"
        fi
    fi
}

# Main execution
log "Starting system cleanup..."

# Check if running as root
check_root

# Create backup directory if needed
if [ "$BACKUP_BEFORE_CLEAN" = true ]; then
    mkdir -p /root/cleanup_backups
fi

# Run cleanup tasks
clean_package_cache
clean_user_cache
clean_temp_files
clean_logs
clean_docker
clean_thumbnails
clean_mail_queue
clean_sessions
clean_trash
clean_journal

# Final disk space report
df -h > "$LOG_DIR/disk_space_after_cleanup.txt"

log "System cleanup completed successfully" 