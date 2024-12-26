#!/bin/bash

# process_monitor.sh - Process monitoring script
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/process_monitor.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Default values if not set in config
: ${LOG_DIR:="./logs"}
: ${HISTORY_DIR:="./history"}
: ${CHECK_INTERVAL:=60}
: ${CPU_THRESHOLD:=80}
: ${MEM_THRESHOLD:=80}
: ${RESTART_DELAY:=5}

# Logging setup
LOG_FILE="$LOG_DIR/process_monitor_$(date +%Y%m%d).log"
mkdir -p "$(dirname "$LOG_FILE")" "$HISTORY_DIR"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to get process CPU usage
get_cpu_usage() {
    local pid="$1"
    local cpu
    cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null)
    echo "${cpu:-0}"
}

# Function to get process memory usage
get_mem_usage() {
    local pid="$1"
    local mem
    mem=$(ps -p "$pid" -o %mem= 2>/dev/null)
    echo "${mem:-0}"
}

# Function to get process uptime
get_process_uptime() {
    local pid="$1"
    local start_time
    start_time=$(ps -p "$pid" -o lstart= 2>/dev/null)
    if [ -n "$start_time" ]; then
        local start_seconds
        start_seconds=$(date -j -f "%a %b %d %T %Y" "$start_time" "+%s")
        local current_seconds
        current_seconds=$(date +%s)
        echo $((current_seconds - start_seconds))
    else
        echo "0"
    fi
}

# Function to check if process is running
is_process_running() {
    local process="$1"
    local pid
    
    if [[ "$process" =~ ^[0-9]+$ ]]; then
        # Process ID provided
        kill -0 "$process" 2>/dev/null
        return $?
    else
        # Process name provided
        pgrep -f "$process" >/dev/null
        return $?
    fi
}

# Function to get process ID
get_process_id() {
    local process="$1"
    
    if [[ "$process" =~ ^[0-9]+$ ]]; then
        echo "$process"
    else
        pgrep -f "$process" | head -1
    fi
}

# Function to restart process
restart_process() {
    local process="$1"
    local command="$2"
    
    log "Attempting to restart $process..."
    
    if [ -n "$command" ]; then
        if eval "$command"; then
            log "Process $process restarted successfully"
            return 0
        else
            log "Failed to restart process $process"
            return 1
        fi
    else
        log "No restart command specified for $process"
        return 1
    fi
}

# Function to record process metrics
record_metrics() {
    local process="$1"
    local pid="$2"
    local cpu="$3"
    local mem="$4"
    local timestamp
    timestamp=$(date +%s)
    
    # Record to history file
    local history_file="$HISTORY_DIR/${process}_$(date +%Y%m%d).csv"
    
    # Create header if file doesn't exist
    if [ ! -f "$history_file" ]; then
        echo "timestamp,pid,cpu,memory" > "$history_file"
    fi
    
    echo "$timestamp,$pid,$cpu,$mem" >> "$history_file"
}

# Function to check process health
check_process_health() {
    local process="$1"
    local restart_cmd="$2"
    local pid
    
    pid=$(get_process_id "$process")
    
    if [ -n "$pid" ]; then
        # Get process metrics
        local cpu
        local mem
        cpu=$(get_cpu_usage "$pid")
        mem=$(get_mem_usage "$pid")
        
        # Record metrics
        record_metrics "$process" "$pid" "$cpu" "$mem"
        
        # Check CPU usage
        if [ "${cpu%.*}" -gt "$CPU_THRESHOLD" ]; then
            log "WARNING: High CPU usage for $process (PID: $pid): $cpu%"
            if [ "$ALERT_ON_HIGH_CPU" = true ]; then
                send_alert "$process" "High CPU usage: $cpu%"
            fi
        fi
        
        # Check memory usage
        if [ "${mem%.*}" -gt "$MEM_THRESHOLD" ]; then
            log "WARNING: High memory usage for $process (PID: $pid): $mem%"
            if [ "$ALERT_ON_HIGH_MEM" = true ]; then
                send_alert "$process" "High memory usage: $mem%"
            fi
        fi
    else
        log "Process $process is not running"
        if [ "$AUTO_RESTART" = true ]; then
            restart_process "$process" "$restart_cmd"
            sleep "$RESTART_DELAY"
        fi
    fi
}

# Function to send alert
send_alert() {
    local process="$1"
    local message="$2"
    
    if [ -n "$EMAIL_RECIPIENT" ]; then
        echo "Process Alert: $process
        
Message: $message
Timestamp: $(date)
Host: $(hostname)" | mail -s "Process Alert: $process" "$EMAIL_RECIPIENT"
    fi
}

# Function to generate daily report
generate_daily_report() {
    if [ "$GENERATE_DAILY_REPORT" = true ]; then
        local report_file="$HISTORY_DIR/daily_report_$(date +%Y%m%d).txt"
        
        {
            echo "Process Monitoring Daily Report"
            echo "=============================="
            echo "Date: $(date)"
            echo "Host: $(hostname)"
            echo ""
            
            for process in $MONITOR_PROCESSES; do
                echo "Process: $process"
                local history_file="$HISTORY_DIR/${process}_$(date +%Y%m%d).csv"
                if [ -f "$history_file" ]; then
                    echo "Average CPU: $(awk -F',' 'NR>1 {sum+=$3} END {print sum/(NR-1)}' "$history_file")%"
                    echo "Average Memory: $(awk -F',' 'NR>1 {sum+=$4} END {print sum/(NR-1)}' "$history_file")%"
                    echo "Restart Count: $(grep -c "Process $process restarted" "$LOG_FILE")"
                fi
                echo ""
            done
        } > "$report_file"
        
        if [ -n "$EMAIL_RECIPIENT" ]; then
            mail -s "Process Monitoring Daily Report - $(hostname)" "$EMAIL_RECIPIENT" < "$report_file"
        fi
    fi
}

# Main execution
log "Starting process monitor..."

# Check if daily report should be generated
if [ "$(date +%H:%M)" = "$DAILY_REPORT_TIME" ]; then
    generate_daily_report
fi

# Monitor processes
while true; do
    for process in $MONITOR_PROCESSES; do
        IFS=':' read -r process_name restart_cmd <<< "$process"
        check_process_health "$process_name" "$restart_cmd"
    done
    
    sleep "$CHECK_INTERVAL"
done 