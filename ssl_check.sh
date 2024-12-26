#!/bin/bash

# ssl_check.sh - SSL certificate checker script
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/ssl_check.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Default values if not set in config
: ${LOG_DIR:="./logs"}
: ${REPORT_DIR:="./reports"}
: ${CACHE_DIR:="./cache"}
: ${WARNING_DAYS:=30}
: ${CRITICAL_DAYS:=7}

# Logging setup
LOG_FILE="$LOG_DIR/ssl_check_$(date +%Y%m%d_%H%M%S).log"
REPORT_FILE="$REPORT_DIR/ssl_check_$(date +%Y%m%d_%H%M%S).txt"
mkdir -p "$(dirname "$LOG_FILE")" "$REPORT_DIR" "$CACHE_DIR"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

report() {
    echo "$1" >> "$REPORT_FILE"
}

# Function to check if OpenSSL is available
check_openssl() {
    if ! command -v openssl &>/dev/null; then
        log "Error: OpenSSL is not installed"
        exit 1
    fi
}

# Function to get certificate expiration date
get_expiry_date() {
    local domain="$1"
    local port="${2:-443}"
    local expiry
    
    # Try to get certificate from server
    expiry=$(echo | openssl s_client -servername "$domain" -connect "$domain:$port" 2>/dev/null | \
             openssl x509 -noout -enddate 2>/dev/null | \
             cut -d= -f2)
    
    echo "$expiry"
}

# Function to get certificate validity
get_cert_validity() {
    local domain="$1"
    local port="${2:-443}"
    local temp_cert="$CACHE_DIR/${domain}_${port}.pem"
    
    # Get certificate from server
    echo | openssl s_client -servername "$domain" -connect "$domain:$port" 2>/dev/null | \
    openssl x509 -outform PEM > "$temp_cert"
    
    if [ -f "$temp_cert" ]; then
        openssl x509 -in "$temp_cert" -noout -text
        rm "$temp_cert"
    fi
}

# Function to calculate days until expiry
days_until_expiry() {
    local expiry_date="$1"
    local expiry_epoch
    local current_epoch
    local days_remaining
    
    expiry_epoch=$(date -j -f "%b %d %T %Y %Z" "$expiry_date" "+%s")
    current_epoch=$(date "+%s")
    days_remaining=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    echo "$days_remaining"
}

# Function to check certificate chain
check_cert_chain() {
    local domain="$1"
    local port="${2:-443}"
    local temp_chain="$CACHE_DIR/${domain}_${port}_chain.pem"
    
    echo | openssl s_client -servername "$domain" -connect "$domain:$port" -showcerts 2>/dev/null > "$temp_chain"
    
    if [ -f "$temp_chain" ]; then
        # Verify certificate chain
        if openssl verify -untrusted "$temp_chain" "$temp_chain" >/dev/null 2>&1; then
            echo "valid"
        else
            echo "invalid"
        fi
        rm "$temp_chain"
    else
        echo "error"
    fi
}

# Function to check certificate strength
check_cert_strength() {
    local domain="$1"
    local port="${2:-443}"
    local strength="strong"
    
    # Check key size
    local key_size
    key_size=$(echo | openssl s_client -servername "$domain" -connect "$domain:$port" 2>/dev/null | \
               openssl x509 -noout -text | grep "Public-Key:" | grep -o "[0-9]*bit")
    
    # Check signature algorithm
    local sig_alg
    sig_alg=$(echo | openssl s_client -servername "$domain" -connect "$domain:$port" 2>/dev/null | \
              openssl x509 -noout -text | grep "Signature Algorithm" | head -1)
    
    if [ "${key_size%bit}" -lt 2048 ]; then
        strength="weak"
    fi
    
    if [[ "$sig_alg" =~ "sha1" ]] || [[ "$sig_alg" =~ "md5" ]]; then
        strength="weak"
    fi
    
    echo "$strength"
}

# Function to send alert
send_alert() {
    local domain="$1"
    local days="$2"
    local level="$3"
    
    if [ -n "$EMAIL_RECIPIENT" ]; then
        echo "SSL Certificate Alert for $domain
        
Level: $level
Days until expiry: $days
Timestamp: $(date)
Host: $(hostname)" | mail -s "SSL Certificate Alert: $domain" "$EMAIL_RECIPIENT"
    fi
}

# Function to check single domain
check_domain() {
    local domain="$1"
    local port="${2:-443}"
    
    log "Checking certificate for $domain:$port"
    report "Domain: $domain:$port"
    report "----------------------------------------"
    
    # Get expiry date
    local expiry_date
    expiry_date=$(get_expiry_date "$domain" "$port")
    
    if [ -n "$expiry_date" ]; then
        local days
        days=$(days_until_expiry "$expiry_date")
        
        report "Expiry Date: $expiry_date"
        report "Days Remaining: $days"
        
        # Check certificate chain
        local chain_status
        chain_status=$(check_cert_chain "$domain" "$port")
        report "Chain Status: $chain_status"
        
        # Check certificate strength
        local cert_strength
        cert_strength=$(check_cert_strength "$domain" "$port")
        report "Certificate Strength: $cert_strength"
        
        # Alert based on expiry
        if [ "$days" -le "$CRITICAL_DAYS" ]; then
            report "Status: CRITICAL - Certificate will expire soon"
            if [ "$ENABLE_ALERTS" = true ]; then
                send_alert "$domain" "$days" "CRITICAL"
            fi
        elif [ "$days" -le "$WARNING_DAYS" ]; then
            report "Status: WARNING - Certificate expiry approaching"
            if [ "$ENABLE_ALERTS" = true ]; then
                send_alert "$domain" "$days" "WARNING"
            fi
        else
            report "Status: OK - Certificate valid"
        fi
        
        # Additional checks if enabled
        if [ "$SHOW_FULL_CHAIN" = true ]; then
            report ""
            report "Certificate Details:"
            get_cert_validity "$domain" "$port" | while read -r line; do
                report "$line"
            done
        fi
    else
        report "Status: ERROR - Could not retrieve certificate"
        if [ "$ENABLE_ALERTS" = true ]; then
            send_alert "$domain" "N/A" "ERROR"
        fi
    fi
    
    report ""
}

# Function to generate summary
generate_summary() {
    report "=== SSL Certificate Check Summary ==="
    report "Timestamp: $(date)"
    report "Total Domains Checked: $(echo "$DOMAINS" | wc -w)"
    report ""
    
    local critical=0
    local warning=0
    local ok=0
    local error=0
    
    while read -r line; do
        case "$line" in
            *"CRITICAL"*) ((critical++));;
            *"WARNING"*) ((warning++));;
            *"OK"*) ((ok++));;
            *"ERROR"*) ((error++));;
        esac
    done < "$REPORT_FILE"
    
    report "Results Summary:"
    report "- Critical: $critical"
    report "- Warning: $warning"
    report "- OK: $ok"
    report "- Error: $error"
}

# Main execution
log "Starting SSL certificate check..."

# Check OpenSSL
check_openssl

# Initialize report
echo "SSL Certificate Check Report" > "$REPORT_FILE"
echo "==========================" >> "$REPORT_FILE"
echo "Generated: $(date)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Check each domain
for domain in $DOMAINS; do
    if [[ "$domain" == *":"* ]]; then
        # Domain includes custom port
        check_domain "${domain%:*}" "${domain#*:}"
    else
        # Use default HTTPS port
        check_domain "$domain"
    fi
done

# Generate summary
generate_summary

# Send report if configured
if [ "$SEND_REPORT" = true ] && [ -n "$EMAIL_RECIPIENT" ]; then
    mail -s "SSL Certificate Check Report - $(hostname)" "$EMAIL_RECIPIENT" < "$REPORT_FILE"
fi

log "SSL certificate check completed. Report saved to: $REPORT_FILE" 