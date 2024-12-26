#!/bin/bash

# backup_rotation.sh - Backup rotation and retention management script
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/backup_rotation.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Default values if not set in config
: ${BACKUP_DIR:="./backups"}
: ${LOG_DIR:="./logs"}
: ${DAILY_RETENTION:=7}
: ${WEEKLY_RETENTION:=4}
: ${MONTHLY_RETENTION:=12}
: ${YEARLY_RETENTION:=5}

# Logging setup
LOG_FILE="$LOG_DIR/backup_rotation_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if a file is older than X days
is_older_than() {
    local file="$1"
    local days="$2"
    local file_time
    file_time=$(stat -f "%m" "$file")
    local current_time
    current_time=$(date +%s)
    local age_seconds=$((current_time - file_time))
    local age_days=$((age_seconds / 86400))
    [ "$age_days" -gt "$days" ]
}

# Function to get backup type from filename
get_backup_type() {
    local filename="$1"
    case "$filename" in
        *_daily_*)
            echo "daily"
            ;;
        *_weekly_*)
            echo "weekly"
            ;;
        *_monthly_*)
            echo "monthly"
            ;;
        *_yearly_*)
            echo "yearly"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Function to rotate backups
rotate_backups() {
    local type="$1"
    local retention="$2"
    local pattern="*_${type}_*"
    local count
    
    log "Processing $type backups..."
    
    # Count files of this type
    count=$(find "$BACKUP_DIR" -type f -name "$pattern" | wc -l)
    
    if [ "$count" -gt "$retention" ]; then
        log "Found $count $type backups, keeping $retention"
        find "$BACKUP_DIR" -type f -name "$pattern" | sort | head -n -"$retention" | while read -r file; do
            if [ -f "$file" ]; then
                log "Removing old $type backup: $file"
                rm "$file"
            fi
        done
    else
        log "Found $count $type backups, no rotation needed"
    fi
}

# Function to promote backups
promote_backups() {
    local from_type="$1"
    local to_type="$2"
    local age_days="$3"
    local pattern="*_${from_type}_*"
    
    log "Checking for $from_type backups to promote to $to_type..."
    
    find "$BACKUP_DIR" -type f -name "$pattern" | while read -r file; do
        if is_older_than "$file" "$age_days"; then
            local new_name
            new_name=$(echo "$file" | sed "s/_${from_type}_/_${to_type}_/")
            log "Promoting $file to $new_name"
            mv "$file" "$new_name"
        fi
    done
}

# Function to clean orphaned backups
clean_orphaned() {
    log "Cleaning orphaned backups..."
    
    find "$BACKUP_DIR" -type f | while read -r file; do
        local type
        type=$(get_backup_type "$(basename "$file")")
        if [ "$type" = "unknown" ]; then
            if [ "$REMOVE_UNKNOWN" = true ]; then
                log "Removing unknown backup: $file"
                rm "$file"
            else
                log "Found unknown backup: $file"
            fi
        fi
    done
}

# Function to verify backup integrity
verify_backups() {
    if [ "$VERIFY_BACKUPS" = true ]; then
        log "Verifying backup integrity..."
        
        find "$BACKUP_DIR" -type f | while read -r file; do
            case "$file" in
                *.tar.gz)
                    if ! tar tzf "$file" >/dev/null 2>&1; then
                        log "Corrupted tar.gz backup: $file"
                        [ "$REMOVE_CORRUPTED" = true ] && rm "$file"
                    fi
                    ;;
                *.zip)
                    if ! unzip -t "$file" >/dev/null 2>&1; then
                        log "Corrupted zip backup: $file"
                        [ "$REMOVE_CORRUPTED" = true ] && rm "$file"
                    fi
                    ;;
                *.sql.gz)
                    if ! gzip -t "$file" >/dev/null 2>&1; then
                        log "Corrupted gzip backup: $file"
                        [ "$REMOVE_CORRUPTED" = true ] && rm "$file"
                    fi
                    ;;
            esac
        done
    fi
}

# Function to calculate and report storage usage
report_storage() {
    if [ "$GENERATE_REPORT" = true ]; then
        log "Generating storage report..."
        
        local total_size
        total_size=$(du -sh "$BACKUP_DIR" | cut -f1)
        
        {
            echo "Backup Storage Report"
            echo "===================="
            echo
            echo "Total backup size: $total_size"
            echo
            echo "Backup counts by type:"
            echo "- Daily: $(find "$BACKUP_DIR" -type f -name "*_daily_*" | wc -l)"
            echo "- Weekly: $(find "$BACKUP_DIR" -type f -name "*_weekly_*" | wc -l)"
            echo "- Monthly: $(find "$BACKUP_DIR" -type f -name "*_monthly_*" | wc -l)"
            echo "- Yearly: $(find "$BACKUP_DIR" -type f -name "*_yearly_*" | wc -l)"
            echo
            echo "Largest backups:"
            find "$BACKUP_DIR" -type f -exec ls -lh {} \; | sort -rh -k5 | head -n 5
        } > "$BACKUP_DIR/storage_report.txt"
        
        if [ -n "$EMAIL_RECIPIENT" ]; then
            mail -s "Backup Storage Report" "$EMAIL_RECIPIENT" < "$BACKUP_DIR/storage_report.txt"
        fi
    fi
}

# Main execution
log "Starting backup rotation process..."

# Verify backup integrity
verify_backups

# Rotate backups by type
rotate_backups "daily" "$DAILY_RETENTION"
rotate_backups "weekly" "$WEEKLY_RETENTION"
rotate_backups "monthly" "$MONTHLY_RETENTION"
rotate_backups "yearly" "$YEARLY_RETENTION"

# Promote backups
promote_backups "daily" "weekly" 7
promote_backups "weekly" "monthly" 30
promote_backups "monthly" "yearly" 365

# Clean orphaned backups
clean_orphaned

# Generate storage report
report_storage

log "Backup rotation completed successfully" 