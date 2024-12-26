#!/bin/bash

# dir_sync.sh - Directory synchronization script
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/dir_sync.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Default values if not set in config
: ${SYNC_INTERVAL:=3600}  # 1 hour
: ${LOG_DIR:="./logs"}
: ${RSYNC_OPTIONS:="-avz --delete"}
: ${EXCLUDE_FILE:=""}

# Logging setup
LOG_FILE="$LOG_DIR/dir_sync_$(date +%Y%m%d).log"
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to validate source and destination
validate_paths() {
    local source="$1"
    local dest="$2"
    
    # Check if source exists
    if [ ! -d "$source" ]; then
        log "Error: Source directory does not exist: $source"
        return 1
    fi
    
    # For remote destinations, check SSH connection
    if [[ "$dest" == *":"* ]]; then
        local host="${dest%%:*}"
        if ! ssh -q "$host" exit; then
            log "Error: Cannot connect to remote host: $host"
            return 1
        fi
    else
        # For local destinations, check if parent directory exists
        local dest_parent="$(dirname "$dest")"
        if [ ! -d "$dest_parent" ]; then
            log "Error: Destination parent directory does not exist: $dest_parent"
            return 1
        fi
    fi
    
    return 0
}

# Function to perform synchronization
sync_directories() {
    local source="$1"
    local dest="$2"
    local name="$3"
    local options="$RSYNC_OPTIONS"
    
    log "Starting synchronization for $name..."
    
    # Add exclude file if specified
    if [ -n "$EXCLUDE_FILE" ] && [ -f "$EXCLUDE_FILE" ]; then
        options="$options --exclude-from=$EXCLUDE_FILE"
    fi
    
    # Add bandwidth limit if specified
    if [ -n "$BANDWIDTH_LIMIT" ]; then
        options="$options --bwlimit=$BANDWIDTH_LIMIT"
    fi
    
    # Perform sync
    if rsync $options "$source/" "$dest/"; then
        log "Synchronization completed successfully for $name"
        
        # Run post-sync hook if specified
        if [ -n "$POST_SYNC_SCRIPT" ] && [ -f "$POST_SYNC_SCRIPT" ]; then
            log "Running post-sync script for $name..."
            if bash "$POST_SYNC_SCRIPT" "$name" "$source" "$dest"; then
                log "Post-sync script completed successfully"
            else
                log "Post-sync script failed"
            fi
        fi
    else
        log "Synchronization failed for $name"
        
        # Send notification if enabled
        if [ "$NOTIFY_ON_ERROR" = true ] && [ -n "$NOTIFICATION_EMAIL" ]; then
            echo "Synchronization failed for $name
            
Source: $source
Destination: $dest
Timestamp: $(date)
Host: $(hostname)

Please check the logs at $LOG_FILE for more details." | mail -s "Sync Error: $name" "$NOTIFICATION_EMAIL"
        fi
    fi
}

# Function to create snapshot if enabled
create_snapshot() {
    local dest="$1"
    local name="$2"
    
    if [ "$ENABLE_SNAPSHOTS" = true ] && [ -n "$SNAPSHOT_DIR" ]; then
        local snapshot_path="$SNAPSHOT_DIR/${name}_$(date +%Y%m%d_%H%M%S)"
        log "Creating snapshot at $snapshot_path..."
        
        if cp -al "$dest" "$snapshot_path"; then
            log "Snapshot created successfully"
            
            # Clean old snapshots if retention is set
            if [ -n "$SNAPSHOT_RETENTION" ]; then
                find "$SNAPSHOT_DIR" -maxdepth 1 -name "${name}_*" -type d -mtime +"$SNAPSHOT_RETENTION" -exec rm -rf {} \;
                log "Cleaned old snapshots"
            fi
        else
            log "Failed to create snapshot"
        fi
    fi
}

# Main execution
log "Starting directory synchronization service..."

# Create snapshot directory if needed
if [ "$ENABLE_SNAPSHOTS" = true ] && [ -n "$SNAPSHOT_DIR" ]; then
    mkdir -p "$SNAPSHOT_DIR"
fi

while true; do
    if [ -n "$SYNC_PAIRS" ]; then
        while IFS=: read -r source dest name; do
            if validate_paths "$source" "$dest"; then
                # Create snapshot of destination if it exists
                if [ -d "$dest" ]; then
                    create_snapshot "$dest" "$name"
                fi
                
                # Perform synchronization
                sync_directories "$source" "$dest" "$name"
            fi
        done <<< "$SYNC_PAIRS"
    else
        log "No sync pairs configured"
        exit 1
    fi
    
    # Sleep if running in continuous mode
    if [ "$RUN_ONCE" = true ]; then
        break
    else
        sleep "$SYNC_INTERVAL"
    fi
done 