#!/bin/bash

# disk_alert.sh - Disk usage monitoring script
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/disk_alert.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Default values if not set in config
: ${CHECK_INTERVAL:=3600}  # 1 hour
: ${ALERT_THRESHOLD:=90}  # percentage
: ${WARNING_THRESHOLD:=80}  # percentage
: ${LOG_DIR:="./logs"}
: ${NOTIFICATION_METHOD:="email"}

# Logging setup
LOG_FILE="$LOG_DIR/disk_alert_$(date +%Y%m%d).log"
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to get disk usage for a mount point
get_disk_usage() {
    local mount_point="$1"
    df -h "$mount_point" | awk 'NR==2 {print $5}' | sed 's/%//'
}

# Function to get disk usage details
get_disk_details() {
    local mount_point="$1"
    df -h "$mount_point" | awk 'NR==2 {print $2,$3,$4,$5,$6}'
}

# Function to get largest directories
get_largest_dirs() {
    local mount_point="$1"
    local count="${2:-5}"
    du -h "$mount_point" 2>/dev/null | sort -rh | head -n "$count"
}

# Function to send email alert
send_email_alert() {
    local mount_point="$1"
    local usage="$2"
    local level="$3"
    local details="$4"
    local dirs="$5"
    
    if [ -n "$EMAIL_RECIPIENT" ]; then
        {
            echo "Disk Usage $level Alert"
            echo
            echo "Mount Point: $mount_point"
            echo "Current Usage: $usage%"
            echo
            echo "Disk Details:"
            echo "Size Used Available Use% Mounted on"
            echo "$details"
            echo
            echo "Largest Directories:"
            echo "$dirs"
            echo
            echo "Timestamp: $(date)"
            echo "Host: $(hostname)"
        } | mail -s "Disk Usage $level Alert: $mount_point at $usage%" "$EMAIL_RECIPIENT"
    fi
}

# Function to send SMS alert
send_sms_alert() {
    local mount_point="$1"
    local usage="$2"
    local level="$3"
    
    if [ -n "$SMS_API_KEY" ] && [ -n "$SMS_TO" ]; then
        local message="$level Alert: $mount_point disk usage at $usage% on $(hostname)"
        curl -X POST "https://api.twilio.com/2010-04-01/Accounts/$SMS_ACCOUNT_SID/Messages.json" \
            --data-urlencode "To=$SMS_TO" \
            --data-urlencode "From=$SMS_FROM" \
            --data-urlencode "Body=$message" \
            -u "$SMS_ACCOUNT_SID:$SMS_API_KEY"
    fi
}

# Function to send notification
send_notification() {
    local mount_point="$1"
    local usage="$2"
    local level="$3"
    local details="$4"
    local dirs="$5"
    
    case "$NOTIFICATION_METHOD" in
        "email")
            send_email_alert "$mount_point" "$usage" "$level" "$details" "$dirs"
            ;;
        "sms")
            send_sms_alert "$mount_point" "$usage" "$level"
            ;;
        *)
            log "Unknown notification method: $NOTIFICATION_METHOD"
            ;;
    esac
}

# Function to check disk usage
check_disk_usage() {
    local mount_point="$1"
    local usage
    local details
    local dirs
    
    usage=$(get_disk_usage "$mount_point")
    
    if [ -z "$usage" ]; then
        log "Error: Could not get disk usage for $mount_point"
        return 1
    fi
    
    log "Checking disk usage for $mount_point: $usage%"
    
    if [ "$usage" -ge "$ALERT_THRESHOLD" ]; then
        details=$(get_disk_details "$mount_point")
        dirs=$(get_largest_dirs "$mount_point")
        log "ALERT: Disk usage above alert threshold on $mount_point: $usage%"
        send_notification "$mount_point" "$usage" "CRITICAL" "$details" "$dirs"
    elif [ "$usage" -ge "$WARNING_THRESHOLD" ]; then
        details=$(get_disk_details "$mount_point")
        dirs=$(get_largest_dirs "$mount_point")
        log "WARNING: Disk usage above warning threshold on $mount_point: $usage%"
        send_notification "$mount_point" "$usage" "WARNING" "$details" "$dirs"
    fi
}

# Main execution
log "Starting disk usage monitoring..."

while true; do
    if [ -n "$MOUNT_POINTS" ]; then
        for mount_point in $MOUNT_POINTS; do
            if [ -d "$mount_point" ]; then
                check_disk_usage "$mount_point"
            else
                log "Mount point not found: $mount_point"
            fi
        done
    else
        log "No mount points configured"
        exit 1
    fi
    
    # Sleep if running in continuous mode
    if [ "$RUN_ONCE" = true ]; then
        break
    else
        sleep "$CHECK_INTERVAL"
    fi
done 