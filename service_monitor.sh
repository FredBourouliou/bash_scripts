#!/bin/bash

# service_monitor.sh - Service monitoring script with alerts
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/service_monitor.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Default values if not set in config
: ${CHECK_INTERVAL:=300}  # 5 minutes
: ${ALERT_INTERVAL:=3600}  # 1 hour
: ${STATUS_FILE:="./status/service_status.json"}
: ${NOTIFICATION_METHOD:="email"}  # email or sms

# Ensure status directory exists
mkdir -p "$(dirname "$STATUS_FILE")"

# Logging setup
LOG_FILE="./logs/service_monitor_$(date +%Y%m%d).log"
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check system service status
check_system_service() {
    local service="$1"
    systemctl is-active --quiet "$service"
    return $?
}

# Function to check port status
check_port() {
    local host="$1"
    local port="$2"
    nc -z -w5 "$host" "$port"
    return $?
}

# Function to check URL status
check_url() {
    local url="$1"
    local expected_code="$2"
    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    [ "$response_code" = "$expected_code" ]
    return $?
}

# Function to send email alert
send_email_alert() {
    local service="$1"
    local status="$2"
    local message="$3"
    
    if [ -n "$EMAIL_RECIPIENT" ]; then
        echo "Service Alert: $service is $status
        
Details: $message
Timestamp: $(date)
Host: $(hostname)" | mail -s "Service Alert: $service $status" "$EMAIL_RECIPIENT"
    fi
}

# Function to send SMS alert
send_sms_alert() {
    local service="$1"
    local status="$2"
    local message="$3"
    
    if [ -n "$SMS_API_KEY" ] && [ -n "$SMS_TO" ]; then
        curl -X POST "https://api.twilio.com/2010-04-01/Accounts/$SMS_ACCOUNT_SID/Messages.json" \
            --data-urlencode "To=$SMS_TO" \
            --data-urlencode "From=$SMS_FROM" \
            --data-urlencode "Body=Service Alert: $service is $status - $message" \
            -u "$SMS_ACCOUNT_SID:$SMS_API_KEY"
    fi
}

# Function to send alert
send_alert() {
    local service="$1"
    local status="$2"
    local message="$3"
    
    # Check if we should send alert (based on last alert time)
    local current_time
    current_time=$(date +%s)
    local last_alert_time
    last_alert_time=$(jq -r ".[\"$service\"].last_alert // 0" "$STATUS_FILE")
    
    if [ $((current_time - last_alert_time)) -ge "$ALERT_INTERVAL" ]; then
        case "$NOTIFICATION_METHOD" in
            "email")
                send_email_alert "$service" "$status" "$message"
                ;;
            "sms")
                send_sms_alert "$service" "$status" "$message"
                ;;
            *)
                log "Unknown notification method: $NOTIFICATION_METHOD"
                ;;
        esac
        
        # Update last alert time
        jq ".[\"$service\"].last_alert = $current_time" "$STATUS_FILE" > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"
    fi
}

# Function to update service status
update_status() {
    local service="$1"
    local status="$2"
    local message="$3"
    
    if [ ! -f "$STATUS_FILE" ]; then
        echo "{}" > "$STATUS_FILE"
    fi
    
    local current_status
    current_status=$(jq -r ".[\"$service\"].status // \"unknown\"" "$STATUS_FILE")
    
    if [ "$status" != "$current_status" ]; then
        jq ".[\"$service\"] = {\"status\": \"$status\", \"message\": \"$message\", \"last_check\": $(date +%s)}" "$STATUS_FILE" > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"
        
        if [ "$status" = "down" ]; then
            send_alert "$service" "$status" "$message"
        fi
    fi
}

# Main monitoring loop
log "Starting service monitoring..."

while true; do
    # Check system services
    if [ -n "$SYSTEM_SERVICES" ]; then
        for service in $SYSTEM_SERVICES; do
            if check_system_service "$service"; then
                update_status "$service" "up" "Service is running"
                log "Service $service is running"
            else
                update_status "$service" "down" "Service is not running"
                log "Service $service is down"
            fi
        done
    fi
    
    # Check ports
    if [ -n "$PORT_CHECKS" ]; then
        while IFS=: read -r host port name; do
            if check_port "$host" "$port"; then
                update_status "$name" "up" "Port $port is accessible"
                log "Port check $name ($host:$port) is successful"
            else
                update_status "$name" "down" "Port $port is not accessible"
                log "Port check $name ($host:$port) failed"
            fi
        done <<< "$PORT_CHECKS"
    fi
    
    # Check URLs
    if [ -n "$URL_CHECKS" ]; then
        while IFS=: read -r url code name; do
            if check_url "$url" "$code"; then
                update_status "$name" "up" "URL returns expected status code"
                log "URL check $name ($url) is successful"
            else
                update_status "$name" "down" "URL does not return expected status code"
                log "URL check $name ($url) failed"
            fi
        done <<< "$URL_CHECKS"
    fi
    
    sleep "$CHECK_INTERVAL"
done 