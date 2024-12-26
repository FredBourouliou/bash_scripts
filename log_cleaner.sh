#!/bin/bash

# log_cleaner.sh - Automated log cleaning and archiving script
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/log_cleaner.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Default values if not set in config
: ${LOG_DIRS:="/var/log"}
: ${ARCHIVE_DIR:="./archives"}
: ${RETENTION_DAYS:=30}
: ${ARCHIVE_RETENTION_DAYS:=90}
: ${LOG_PATTERNS:="*.log"}
: ${COMPRESS_LOGS:=true}

# Ensure archive directory exists
mkdir -p "$ARCHIVE_DIR"

# Logging setup
LOG_FILE="./logs/log_cleaner_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to archive old logs
archive_logs() {
    local dir="$1"
    local pattern="$2"
    
    log "Archiving logs in $dir matching pattern $pattern"
    
    find "$dir" -type f -name "$pattern" -mtime +$RETENTION_DAYS | while read -r file; do
        if [ -f "$file" ]; then
            archive_name="$(basename "$file")_$(date +%Y%m%d_%H%M%S)"
            if [ "$COMPRESS_LOGS" = true ]; then
                if gzip -c "$file" > "$ARCHIVE_DIR/${archive_name}.gz"; then
                    log "Archived and compressed: $file"
                    rm "$file"
                else
                    log "Failed to archive: $file"
                fi
            else
                if mv "$file" "$ARCHIVE_DIR/$archive_name"; then
                    log "Archived: $file"
                else
                    log "Failed to archive: $file"
                fi
            fi
        fi
    done
}

# Function to clean old archives
clean_old_archives() {
    log "Cleaning old archives..."
    find "$ARCHIVE_DIR" -type f -mtime +$ARCHIVE_RETENTION_DAYS -delete
    log "Old archives cleaned"
}

# Function to truncate active logs
truncate_active_logs() {
    if [ -n "$TRUNCATE_PATTERNS" ]; then
        log "Truncating active logs..."
        for pattern in $TRUNCATE_PATTERNS; do
            for dir in $LOG_DIRS; do
                find "$dir" -type f -name "$pattern" | while read -r file; do
                    if [ -f "$file" ]; then
                        : > "$file"
                        log "Truncated: $file"
                    fi
                done
            done
        done
    fi
}

# Main execution
log "Starting log cleaning process..."

# Process each log directory
for dir in $LOG_DIRS; do
    if [ -d "$dir" ]; then
        for pattern in $LOG_PATTERNS; do
            archive_logs "$dir" "$pattern"
        done
    else
        log "Directory not found: $dir"
    fi
done

# Clean old archives
clean_old_archives

# Truncate specified active logs
truncate_active_logs

log "Log cleaning process completed" 