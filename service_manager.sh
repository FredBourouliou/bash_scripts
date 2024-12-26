#!/bin/bash

# service_manager.sh - Service management script
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/service_manager.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Default values if not set in config
: ${LOG_DIR:="./logs"}
: ${STATUS_DIR:="./status"}
: ${CHECK_INTERVAL:=60}
: ${RETRY_ATTEMPTS:=3}
: ${RETRY_DELAY:=5}

# Logging setup
LOG_FILE="$LOG_DIR/service_manager_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")" "$STATUS_DIR"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if systemd is available
check_systemd() {
    if command -v systemctl &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to check service status
check_service_status() {
    local service="$1"
    
    if check_systemd; then
        systemctl is-active --quiet "$service"
        return $?
    else
        service "$service" status &>/dev/null
        return $?
    fi
}

# Function to start service
start_service() {
    local service="$1"
    local attempts=0
    
    while [ $attempts -lt "$RETRY_ATTEMPTS" ]; do
        log "Attempting to start service: $service (attempt $((attempts + 1)))"
        
        if check_systemd; then
            systemctl start "$service"
        else
            service "$service" start
        fi
        
        if check_service_status "$service"; then
            log "Service started successfully: $service"
            return 0
        fi
        
        ((attempts++))
        [ $attempts -lt "$RETRY_ATTEMPTS" ] && sleep "$RETRY_DELAY"
    done
    
    log "Failed to start service after $RETRY_ATTEMPTS attempts: $service"
    return 1
}

# Function to stop service
stop_service() {
    local service="$1"
    
    log "Stopping service: $service"
    
    if check_systemd; then
        systemctl stop "$service"
    else
        service "$service" stop
    fi
    
    if ! check_service_status "$service"; then
        log "Service stopped successfully: $service"
        return 0
    else
        log "Failed to stop service: $service"
        return 1
    fi
}

# Function to restart service
restart_service() {
    local service="$1"
    
    log "Restarting service: $service"
    
    if check_systemd; then
        systemctl restart "$service"
    else
        service "$service" restart
    fi
    
    if check_service_status "$service"; then
        log "Service restarted successfully: $service"
        return 0
    else
        log "Failed to restart service: $service"
        return 1
    fi
}

# Function to get service details
get_service_details() {
    local service="$1"
    local details=""
    
    if check_systemd; then
        details=$(systemctl status "$service" 2>/dev/null)
    else
        details=$(service "$service" status 2>/dev/null)
    fi
    
    echo "$details"
}

# Function to check service dependencies
check_dependencies() {
    local service="$1"
    local dependencies=""
    
    if check_systemd; then
        dependencies=$(systemctl list-dependencies "$service" --no-pager 2>/dev/null)
    fi
    
    echo "$dependencies"
}

# Function to monitor service resources
monitor_resources() {
    local service="$1"
    local pid
    
    # Get service PID
    if check_systemd; then
        pid=$(systemctl show -p MainPID "$service" 2>/dev/null | cut -d= -f2)
    else
        pid=$(pgrep -f "$service" | head -1)
    fi
    
    if [ -n "$pid" ] && [ "$pid" -gt 0 ]; then
        # Get CPU usage
        local cpu
        cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null)
        
        # Get memory usage
        local mem
        mem=$(ps -p "$pid" -o %mem= 2>/dev/null)
        
        # Get process uptime
        local uptime
        uptime=$(ps -p "$pid" -o etime= 2>/dev/null)
        
        echo "CPU: ${cpu}%"
        echo "Memory: ${mem}%"
        echo "Uptime: $uptime"
    else
        echo "Service not running"
    fi
}

# Function to check service logs
check_service_logs() {
    local service="$1"
    local lines="${2:-50}"
    
    if check_systemd; then
        journalctl -u "$service" -n "$lines" --no-pager
    else
        if [ -f "/var/log/$service.log" ]; then
            tail -n "$lines" "/var/log/$service.log"
        fi
    fi
}

# Function to send notification
send_notification() {
    local service="$1"
    local status="$2"
    local message="$3"
    
    if [ "$SEND_NOTIFICATIONS" = true ] && [ -n "$EMAIL_RECIPIENT" ]; then
        echo "Service Alert: $service
        
Status: $status
Message: $message
Timestamp: $(date)
Host: $(hostname)

Service Details:
$(get_service_details "$service")" | mail -s "Service Alert: $service - $status" "$EMAIL_RECIPIENT"
    fi
}

# Function to generate service report
generate_report() {
    local report_file="$STATUS_DIR/service_report_$(date +%Y%m%d).txt"
    
    {
        echo "Service Status Report"
        echo "===================="
        echo "Generated: $(date)"
        echo "Host: $(hostname)"
        echo
        
        for service in $MONITORED_SERVICES; do
            echo "Service: $service"
            echo "----------"
            echo "Status: $(check_service_status "$service" && echo "Running" || echo "Stopped")"
            echo
            echo "Resource Usage:"
            monitor_resources "$service"
            echo
            echo "Recent Logs:"
            check_service_logs "$service" 10
            echo
            echo "Dependencies:"
            check_dependencies "$service"
            echo
            echo
        done
        
    } > "$report_file"
    
    if [ "$SEND_REPORT" = true ] && [ -n "$EMAIL_RECIPIENT" ]; then
        mail -s "Service Status Report - $(hostname)" "$EMAIL_RECIPIENT" < "$report_file"
    fi
    
    log "Report generated: $report_file"
}

# Function to monitor services
monitor_services() {
    while true; do
        for service in $MONITORED_SERVICES; do
            if ! check_service_status "$service"; then
                log "Service $service is down"
                
                if [ "$AUTO_RESTART" = true ]; then
                    log "Attempting to restart $service"
                    if restart_service "$service"; then
                        send_notification "$service" "Restarted" "Service was down and has been automatically restarted"
                    else
                        send_notification "$service" "Failed" "Service is down and automatic restart failed"
                    fi
                else
                    send_notification "$service" "Down" "Service is down"
                fi
            else
                # Check resource usage
                local cpu
                cpu=$(monitor_resources "$service" | grep "CPU:" | cut -d: -f2 | tr -d ' %')
                local mem
                mem=$(monitor_resources "$service" | grep "Memory:" | cut -d: -f2 | tr -d ' %')
                
                if [ -n "$cpu" ] && [ "${cpu%.*}" -gt "$CPU_THRESHOLD" ]; then
                    send_notification "$service" "Warning" "High CPU usage: $cpu%"
                fi
                
                if [ -n "$mem" ] && [ "${mem%.*}" -gt "$MEM_THRESHOLD" ]; then
                    send_notification "$service" "Warning" "High memory usage: $mem%"
                fi
            fi
        done
        
        sleep "$CHECK_INTERVAL"
    done
}

# Main execution
log "Starting service manager..."

# Process command line arguments
case "$1" in
    "start")
        if [ -z "$2" ]; then
            echo "Usage: $0 start <service>"
            exit 1
        fi
        start_service "$2"
        ;;
    "stop")
        if [ -z "$2" ]; then
            echo "Usage: $0 stop <service>"
            exit 1
        fi
        stop_service "$2"
        ;;
    "restart")
        if [ -z "$2" ]; then
            echo "Usage: $0 restart <service>"
            exit 1
        fi
        restart_service "$2"
        ;;
    "status")
        if [ -z "$2" ]; then
            echo "Usage: $0 status <service>"
            exit 1
        fi
        get_service_details "$2"
        ;;
    "monitor")
        monitor_services
        ;;
    "report")
        generate_report
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|monitor|report} [service]"
        exit 1
        ;;
esac

log "Service manager completed" 