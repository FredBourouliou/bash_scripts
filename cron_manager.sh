#!/bin/bash

# cron_manager.sh - Cron job management script
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/cron_manager.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Default values if not set in config
: ${LOG_DIR:="./logs"}
: ${CRON_DIR:="/etc/cron.d"}
: ${BACKUP_DIR:="./backups"}
: ${TEMPLATE_DIR:="./templates"}

# Logging setup
LOG_FILE="$LOG_DIR/cron_manager_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_DIR"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to validate cron expression
validate_cron() {
    local expression="$1"
    local valid=true
    
    # Split expression into fields
    IFS=' ' read -r minute hour day month weekday command <<< "$expression"
    
    # Validate minute (0-59)
    if ! [[ "$minute" =~ ^[0-9*,/-]+$ ]] || [[ "$minute" =~ [0-9]+ ]] && [ "$minute" -gt 59 ]; then
        valid=false
    fi
    
    # Validate hour (0-23)
    if ! [[ "$hour" =~ ^[0-9*,/-]+$ ]] || [[ "$hour" =~ [0-9]+ ]] && [ "$hour" -gt 23 ]; then
        valid=false
    fi
    
    # Validate day (1-31)
    if ! [[ "$day" =~ ^[0-9*,/-]+$ ]] || [[ "$day" =~ [0-9]+ ]] && [ "$day" -gt 31 ]; then
        valid=false
    fi
    
    # Validate month (1-12)
    if ! [[ "$month" =~ ^[0-9*,/-]+$ ]] || [[ "$month" =~ [0-9]+ ]] && [ "$month" -gt 12 ]; then
        valid=false
    fi
    
    # Validate weekday (0-7)
    if ! [[ "$weekday" =~ ^[0-9*,/-]+$ ]] || [[ "$weekday" =~ [0-9]+ ]] && [ "$weekday" -gt 7 ]; then
        valid=false
    fi
    
    [ "$valid" = true ]
}

# Function to backup crontabs
backup_crontabs() {
    local backup_file="$BACKUP_DIR/crontabs_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    log "Backing up crontabs..."
    if tar -czf "$backup_file" -C / etc/cron.d etc/crontab /var/spool/cron 2>/dev/null; then
        log "Backup created: $backup_file"
        return 0
    else
        log "Failed to create backup"
        return 1
    fi
}

# Function to list all cron jobs
list_cron_jobs() {
    log "Listing all cron jobs..."
    
    # System-wide crontab
    echo "System-wide crontab (/etc/crontab):"
    cat /etc/crontab 2>/dev/null
    echo
    
    # User crontabs
    echo "User crontabs:"
    for user in $(cut -d: -f1 /etc/passwd); do
        crontab -l -u "$user" 2>/dev/null | while read -r line; do
            echo "$user: $line"
        done
    done
    echo
    
    # Cron.d directory
    echo "Cron.d directory contents:"
    for file in /etc/cron.d/*; do
        if [ -f "$file" ]; then
            echo "File: $file"
            cat "$file" 2>/dev/null
            echo
        fi
    done
}

# Function to add cron job
add_cron_job() {
    local user="$1"
    local schedule="$2"
    local command="$3"
    local description="$4"
    
    # Validate cron expression
    if ! validate_cron "$schedule $command"; then
        log "Invalid cron expression: $schedule"
        return 1
    fi
    
    # Create temporary file
    local temp_file
    temp_file=$(mktemp)
    
    # Export current crontab
    crontab -l -u "$user" 2>/dev/null > "$temp_file"
    
    # Add new job with description
    {
        echo "# $description"
        echo "$schedule $command"
    } >> "$temp_file"
    
    # Install new crontab
    if crontab -u "$user" "$temp_file"; then
        log "Added cron job for user $user: $schedule $command"
        rm "$temp_file"
        return 0
    else
        log "Failed to add cron job for user $user"
        rm "$temp_file"
        return 1
    fi
}

# Function to remove cron job
remove_cron_job() {
    local user="$1"
    local pattern="$2"
    
    # Create temporary file
    local temp_file
    temp_file=$(mktemp)
    
    # Export and filter current crontab
    crontab -l -u "$user" 2>/dev/null | grep -v "$pattern" > "$temp_file"
    
    # Install new crontab
    if crontab -u "$user" "$temp_file"; then
        log "Removed cron job matching pattern: $pattern"
        rm "$temp_file"
        return 0
    else
        log "Failed to remove cron job"
        rm "$temp_file"
        return 1
    fi
}

# Function to check cron job status
check_cron_status() {
    # Check if cron daemon is running
    if pgrep -x "cron" >/dev/null; then
        log "Cron daemon is running"
    else
        log "Warning: Cron daemon is not running"
    fi
    
    # Check cron log
    if [ -f "/var/log/cron" ]; then
        echo "Recent cron activity:"
        tail -n 20 /var/log/cron
    fi
}

# Function to generate cron report
generate_report() {
    local report_file="$LOG_DIR/cron_report_$(date +%Y%m%d).txt"
    
    {
        echo "Cron Jobs Report"
        echo "================"
        echo "Generated: $(date)"
        echo "Host: $(hostname)"
        echo
        
        echo "Active Cron Jobs:"
        echo "----------------"
        list_cron_jobs
        
        echo "Cron Service Status:"
        echo "------------------"
        systemctl status cron 2>/dev/null || service cron status 2>/dev/null
        
        echo
        echo "Recent Cron Activity:"
        echo "-------------------"
        grep CRON /var/log/syslog | tail -n 20
        
    } > "$report_file"
    
    if [ "$SEND_REPORT" = true ] && [ -n "$EMAIL_RECIPIENT" ]; then
        mail -s "Cron Jobs Report - $(hostname)" "$EMAIL_RECIPIENT" < "$report_file"
    fi
    
    log "Report generated: $report_file"
}

# Function to apply cron template
apply_template() {
    local template="$1"
    local user="$2"
    
    if [ -f "$TEMPLATE_DIR/$template" ]; then
        log "Applying template: $template"
        
        while IFS= read -r line; do
            if [[ "$line" =~ ^#.*$ ]] || [[ -z "$line" ]]; then
                continue
            fi
            
            if validate_cron "$line"; then
                add_cron_job "$user" "$line"
            else
                log "Invalid entry in template: $line"
            fi
        done < "$TEMPLATE_DIR/$template"
    else
        log "Template not found: $template"
        return 1
    fi
}

# Main execution
log "Starting cron manager..."

# Process command line arguments
case "$1" in
    "list")
        list_cron_jobs
        ;;
    "add")
        if [ $# -lt 4 ]; then
            echo "Usage: $0 add <user> <schedule> <command> [description]"
            exit 1
        fi
        add_cron_job "$2" "$3" "$4" "${5:-No description}"
        ;;
    "remove")
        if [ $# -lt 3 ]; then
            echo "Usage: $0 remove <user> <pattern>"
            exit 1
        fi
        remove_cron_job "$2" "$3"
        ;;
    "status")
        check_cron_status
        ;;
    "backup")
        backup_crontabs
        ;;
    "report")
        generate_report
        ;;
    "template")
        if [ $# -lt 3 ]; then
            echo "Usage: $0 template <template_name> <user>"
            exit 1
        fi
        apply_template "$2" "$3"
        ;;
    *)
        echo "Usage: $0 {list|add|remove|status|backup|report|template}"
        exit 1
        ;;
esac

log "Cron manager completed" 