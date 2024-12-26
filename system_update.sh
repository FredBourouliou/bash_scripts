#!/bin/bash

# system_update.sh - System update management script
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/system_update.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Default values if not set in config
: ${LOG_DIR:="./logs"}
: ${BACKUP_DIR:="./backups"}
: ${SNAPSHOT_DIR:="./snapshots"}
: ${UPDATE_CACHE_DIR:="/var/cache/apt/archives"}
: ${PRE_UPDATE_SCRIPT:=""}
: ${POST_UPDATE_SCRIPT:=""}

# Logging setup
LOG_FILE="$LOG_DIR/system_update_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_DIR"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to detect package manager
detect_package_manager() {
    if command -v apt &>/dev/null; then
        echo "apt"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v brew &>/dev/null; then
        echo "brew"
    else
        echo "unknown"
    fi
}

# Function to check system requirements
check_requirements() {
    local pkg_mgr
    pkg_mgr=$(detect_package_manager)
    
    if [ "$pkg_mgr" = "unknown" ]; then
        log "Error: No supported package manager found"
        exit 1
    fi
    
    if [ "$(id -u)" -ne 0 ] && [ "$pkg_mgr" != "brew" ]; then
        log "Error: This script must be run as root"
        exit 1
    fi
}

# Function to create system snapshot
create_snapshot() {
    if [ "$ENABLE_SNAPSHOTS" = true ] && [ -n "$SNAPSHOT_DIR" ]; then
        log "Creating system snapshot..."
        local snapshot_name="system_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$SNAPSHOT_DIR"
        
        case "$(detect_package_manager)" in
            "apt")
                dpkg --get-selections > "$SNAPSHOT_DIR/${snapshot_name}_packages.list"
                cp -r /etc/apt/sources.list* "$SNAPSHOT_DIR/${snapshot_name}_sources/"
                ;;
            "yum"|"dnf")
                rpm -qa > "$SNAPSHOT_DIR/${snapshot_name}_packages.list"
                cp -r /etc/yum.repos.d/ "$SNAPSHOT_DIR/${snapshot_name}_repos/"
                ;;
            "brew")
                brew list > "$SNAPSHOT_DIR/${snapshot_name}_packages.list"
                ;;
        esac
        
        if [ "$BACKUP_CONFIG" = true ]; then
            tar -czf "$SNAPSHOT_DIR/${snapshot_name}_etc.tar.gz" /etc/
        fi
        
        log "Snapshot created: $snapshot_name"
    fi
}

# Function to clean old snapshots
clean_old_snapshots() {
    if [ -n "$SNAPSHOT_RETENTION" ] && [ -d "$SNAPSHOT_DIR" ]; then
        log "Cleaning old snapshots..."
        find "$SNAPSHOT_DIR" -type f -mtime +"$SNAPSHOT_RETENTION" -delete
        find "$SNAPSHOT_DIR" -type d -empty -delete
    fi
}

# Function to update package lists
update_package_lists() {
    log "Updating package lists..."
    
    case "$(detect_package_manager)" in
        "apt")
            apt-get update
            ;;
        "yum")
            yum check-update
            ;;
        "dnf")
            dnf check-update
            ;;
        "brew")
            brew update
            ;;
    esac
}

# Function to get available updates
get_available_updates() {
    case "$(detect_package_manager)" in
        "apt")
            apt-get -s upgrade | grep -P '^\d+ upgraded'
            ;;
        "yum")
            yum check-update | grep -v '^$' | grep -v '^Last' | wc -l
            ;;
        "dnf")
            dnf check-update | grep -v '^$' | grep -v '^Last' | wc -l
            ;;
        "brew")
            brew outdated | wc -l
            ;;
    esac
}

# Function to perform system update
perform_update() {
    log "Starting system update..."
    
    case "$(detect_package_manager)" in
        "apt")
            if [ "$DIST_UPGRADE" = true ]; then
                apt-get dist-upgrade -y
            else
                apt-get upgrade -y
            fi
            ;;
        "yum")
            yum update -y
            ;;
        "dnf")
            dnf upgrade -y
            ;;
        "brew")
            brew upgrade
            ;;
    esac
}

# Function to clean package cache
clean_package_cache() {
    if [ "$CLEAN_CACHE" = true ]; then
        log "Cleaning package cache..."
        
        case "$(detect_package_manager)" in
            "apt")
                apt-get clean
                apt-get autoclean
                ;;
            "yum")
                yum clean all
                ;;
            "dnf")
                dnf clean all
                ;;
            "brew")
                brew cleanup
                ;;
        esac
    fi
}

# Function to remove unused packages
remove_unused_packages() {
    if [ "$REMOVE_UNUSED" = true ]; then
        log "Removing unused packages..."
        
        case "$(detect_package_manager)" in
            "apt")
                apt-get autoremove -y
                ;;
            "yum")
                package-cleanup --leaves
                ;;
            "dnf")
                dnf autoremove -y
                ;;
            "brew")
                brew autoremove
                ;;
        esac
    fi
}

# Function to check system status
check_system_status() {
    log "Checking system status..."
    
    # Check disk space
    df -h
    
    # Check memory usage
    free -h
    
    # Check load average
    uptime
    
    # Check running services
    if command -v systemctl &>/dev/null; then
        systemctl list-units --state=failed
    fi
}

# Function to send notification
send_notification() {
    local subject="$1"
    local message="$2"
    
    if [ -n "$EMAIL_RECIPIENT" ]; then
        echo "$message" | mail -s "$subject" "$EMAIL_RECIPIENT"
    fi
}

# Function to run custom script
run_custom_script() {
    local script="$1"
    local description="$2"
    
    if [ -n "$script" ] && [ -f "$script" ] && [ -x "$script" ]; then
        log "Running $description: $script"
        if ! "$script"; then
            log "Warning: $description failed"
            return 1
        fi
    fi
    return 0
}

# Main execution
log "Starting system update process..."

# Check requirements
check_requirements

# Create snapshot before update
create_snapshot

# Run pre-update script
run_custom_script "$PRE_UPDATE_SCRIPT" "pre-update script"

# Update package lists
update_package_lists

# Get number of available updates
updates_available=$(get_available_updates)
log "Available updates: $updates_available"

if [ -n "$updates_available" ]; then
    # Perform update
    perform_update
    
    # Clean package cache
    clean_package_cache
    
    # Remove unused packages
    remove_unused_packages
    
    # Run post-update script
    run_custom_script "$POST_UPDATE_SCRIPT" "post-update script"
    
    # Check system status
    check_system_status
    
    # Clean old snapshots
    clean_old_snapshots
    
    # Send notification
    if [ "$SEND_NOTIFICATIONS" = true ]; then
        send_notification "System Update Complete - $(hostname)" "System update completed successfully.
        
Updates installed: $updates_available
Timestamp: $(date)
Log file: $LOG_FILE"
    fi
else
    log "No updates available"
    if [ "$SEND_NOTIFICATIONS" = true ]; then
        send_notification "System Update Check - $(hostname)" "No updates available.
        
Timestamp: $(date)"
    fi
fi

log "System update process completed" 