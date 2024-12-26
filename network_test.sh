#!/bin/bash

# network_test.sh - Network diagnostic script
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/network_test.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Default values if not set in config
: ${LOG_DIR:="./logs"}
: ${REPORT_DIR:="./reports"}
: ${PING_COUNT:=4}
: ${TRACEROUTE_MAX_TTL:=30}
: ${SPEED_TEST_DURATION:=10}
: ${DNS_SERVERS:="8.8.8.8 8.8.4.4 1.1.1.1"}

# Logging setup
LOG_FILE="$LOG_DIR/network_test_$(date +%Y%m%d_%H%M%S).log"
REPORT_FILE="$REPORT_DIR/network_test_$(date +%Y%m%d_%H%M%S).txt"
mkdir -p "$(dirname "$LOG_FILE")" "$REPORT_DIR"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

report() {
    echo "$1" >> "$REPORT_FILE"
}

# Function to check required tools
check_requirements() {
    local missing_tools=()
    
    for tool in ping traceroute nc curl dig iperf3; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log "Error: Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
}

# Function to test connectivity
test_connectivity() {
    report "=== Connectivity Tests ==="
    report ""
    
    for host in $TEST_HOSTS; do
        report "Testing connectivity to $host:"
        if ping -c "$PING_COUNT" "$host" &>/dev/null; then
            local ping_stats
            ping_stats=$(ping -c "$PING_COUNT" "$host" | tail -1)
            report "Success: $ping_stats"
        else
            report "Failed to reach $host"
        fi
        report ""
    done
}

# Function to perform traceroute
perform_traceroute() {
    report "=== Traceroute Tests ==="
    report ""
    
    for host in $TEST_HOSTS; do
        report "Traceroute to $host:"
        traceroute -m "$TRACEROUTE_MAX_TTL" "$host" 2>&1 | while read -r line; do
            report "$line"
        done
        report ""
    done
}

# Function to test bandwidth
test_bandwidth() {
    if [ "$ENABLE_SPEED_TEST" = true ]; then
        report "=== Bandwidth Tests ==="
        report ""
        
        if command -v iperf3 &>/dev/null; then
            for server in $IPERF_SERVERS; do
                report "Testing bandwidth to $server:"
                if iperf3 -c "$server" -t "$SPEED_TEST_DURATION" -J 2>/dev/null | grep -q "bits_per_second"; then
                    local speed
                    speed=$(iperf3 -c "$server" -t "$SPEED_TEST_DURATION" -J 2>/dev/null | 
                           jq -r '.end.sum_received.bits_per_second / 1000000 | floor' 2>/dev/null)
                    report "Speed: ${speed}Mbps"
                else
                    report "Failed to test bandwidth to $server"
                fi
                report ""
            done
        else
            # Fallback to basic speed test
            report "Testing download speed (curl):"
            local speed_file="/tmp/speedtest_$(date +%s)"
            curl -o "$speed_file" "$SPEED_TEST_URL" 2>/dev/null &
            local pid=$!
            local size=0
            local start
            start=$(date +%s)
            
            while kill -0 $pid 2>/dev/null; do
                if [ -f "$speed_file" ]; then
                    size=$(stat -f %z "$speed_file")
                fi
                sleep 1
            done
            
            local end
            end=$(date +%s)
            local duration=$((end - start))
            local speed=$((size * 8 / duration / 1000000))
            report "Average speed: ${speed}Mbps"
            rm -f "$speed_file"
        fi
    fi
}

# Function to test ports
test_ports() {
    report "=== Port Tests ==="
    report ""
    
    for target in $PORT_TESTS; do
        local host
        local port
        host=$(echo "$target" | cut -d: -f1)
        port=$(echo "$target" | cut -d: -f2)
        
        report "Testing $host:$port:"
        if nc -zv -w5 "$host" "$port" 2>&1 | grep -q "succeeded"; then
            report "Port $port is open"
        else
            report "Port $port is closed"
        fi
        report ""
    done
}

# Function to perform DNS tests
test_dns() {
    report "=== DNS Tests ==="
    report ""
    
    for server in $DNS_SERVERS; do
        report "Testing DNS server $server:"
        
        # Test resolution time
        local start
        start=$(date +%s%N)
        if dig @"$server" "$DNS_TEST_DOMAIN" +short &>/dev/null; then
            local end
            end=$(date +%s%N)
            local duration
            duration=$(( (end - start) / 1000000 ))
            report "Resolution successful (${duration}ms)"
            
            # Get resolved IP
            local ip
            ip=$(dig @"$server" "$DNS_TEST_DOMAIN" +short)
            report "Resolved IP: $ip"
        else
            report "DNS resolution failed"
        fi
        report ""
    done
}

# Function to generate summary
generate_summary() {
    report "=== Network Test Summary ==="
    report "Timestamp: $(date)"
    report "Hostname: $(hostname)"
    report ""
    
    # Get network interface information
    report "Network Interfaces:"
    ifconfig | grep -E "^[a-z]|inet " | while read -r line; do
        report "$line"
    done
    report ""
    
    # Get routing information
    report "Routing Table:"
    netstat -rn | while read -r line; do
        report "$line"
    done
    report ""
    
    # Get current connections
    report "Current Connections:"
    netstat -an | grep ESTABLISHED | while read -r line; do
        report "$line"
    done
}

# Main execution
log "Starting network diagnostics..."

# Check requirements
check_requirements

# Initialize report
echo "Network Diagnostic Report" > "$REPORT_FILE"
echo "=======================" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Run tests
test_connectivity
perform_traceroute
test_bandwidth
test_ports
test_dns

# Generate summary
generate_summary

# Export results if configured
if [ -n "$EMAIL_RECIPIENT" ]; then
    mail -s "Network Diagnostic Report - $(hostname)" "$EMAIL_RECIPIENT" < "$REPORT_FILE"
fi

log "Network diagnostics completed. Report saved to: $REPORT_FILE" 