#!/bin/bash

# security_audit.sh - Security audit script
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/security_audit.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Default values if not set in config
: ${REPORT_DIR:="./reports"}
: ${LOG_DIR:="./logs"}
: ${CRITICAL_SERVICES:="sshd nginx apache2 mysql postgresql"}
: ${CHECK_PORTS:="22 80 443 3306 5432"}

# Logging setup
LOG_FILE="$LOG_DIR/security_audit_$(date +%Y%m%d_%H%M%S).log"
REPORT_FILE="$REPORT_DIR/security_audit_$(date +%Y%m%d_%H%M%S).txt"
mkdir -p "$(dirname "$LOG_FILE")" "$REPORT_DIR"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

report() {
    echo "$1" >> "$REPORT_FILE"
}

# Function to check if running as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        log "Error: This script must be run as root"
        exit 1
    fi
}

# Function to check system updates
check_updates() {
    report "=== System Updates ==="
    report ""
    
    if [ -f /etc/debian_version ]; then
        apt-get update &>/dev/null
        updates=$(apt-get -s upgrade | grep -P '^\d+ upgraded' | cut -d" " -f1)
        security_updates=$(apt-get -s upgrade | grep -i security | wc -l)
    elif [ -f /etc/redhat-release ]; then
        updates=$(yum check-update --quiet | grep -v "^$" | wc -l)
        security_updates=$(yum check-update --security --quiet | grep -v "^$" | wc -l)
    fi
    
    report "Pending updates: $updates"
    report "Security updates: $security_updates"
    report ""
}

# Function to check user accounts
check_users() {
    report "=== User Accounts ==="
    report ""
    
    # Check for users with empty passwords
    empty_pass=$(awk -F: '($2 == "" ) { print $1 }' /etc/shadow)
    if [ -n "$empty_pass" ]; then
        report "WARNING: Users with empty passwords found:"
        report "$empty_pass"
    fi
    
    # Check for users with UID 0
    root_users=$(awk -F: '($3 == 0) { print $1 }' /etc/passwd)
    report "Users with UID 0:"
    report "$root_users"
    
    # List sudo users
    sudo_users=$(grep -Po '^sudo.+:\K.*$' /etc/group)
    report "Users with sudo access:"
    report "$sudo_users"
    
    report ""
}

# Function to check file permissions
check_permissions() {
    report "=== File Permissions ==="
    report ""
    
    # Check world-writable files
    report "World-writable files in system directories:"
    find /etc /bin /sbin /usr/bin /usr/sbin -type f -perm -0002 2>/dev/null | while read -r file; do
        report "WARNING: $file is world-writable"
    done
    
    # Check SUID/SGID files
    report "SUID/SGID files:"
    find / -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | while read -r file; do
        report "$file"
    done
    
    report ""
}

# Function to check network security
check_network() {
    report "=== Network Security ==="
    report ""
    
    # Check listening ports
    report "Listening ports:"
    if command -v ss &>/dev/null; then
        ss -tuln | grep LISTEN
    else
        netstat -tuln | grep LISTEN
    fi
    report ""
    
    # Check firewall status
    report "Firewall status:"
    if command -v ufw &>/dev/null; then
        ufw status
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --list-all
    fi
    report ""
}

# Function to check service security
check_services() {
    report "=== Service Security ==="
    report ""
    
    # Check critical services
    for service in $CRITICAL_SERVICES; do
        if systemctl is-active --quiet "$service"; then
            report "$service: Running"
        else
            report "WARNING: $service is not running"
        fi
    done
    
    # Check for unnecessary services
    report "Running services:"
    systemctl list-units --type=service --state=running
    
    report ""
}

# Function to check SSH security
check_ssh() {
    report "=== SSH Security ==="
    report ""
    
    if [ -f "/etc/ssh/sshd_config" ]; then
        # Check SSH configuration
        report "SSH Configuration:"
        grep -E "^(PermitRootLogin|PasswordAuthentication|Port)" /etc/ssh/sshd_config
        
        # Check SSH keys
        report "Authorized SSH keys:"
        for user_home in /home/*; do
            user=$(basename "$user_home")
            if [ -f "$user_home/.ssh/authorized_keys" ]; then
                report "User: $user"
                report "Keys: $(wc -l < "$user_home/.ssh/authorized_keys") authorized keys"
            fi
        done
    else
        report "SSH server is not installed"
    fi
    
    report ""
}

# Function to check system logs
check_logs() {
    report "=== System Logs ==="
    report ""
    
    # Check authentication failures
    report "Recent authentication failures:"
    grep "authentication failure" /var/log/auth.log 2>/dev/null | tail -n 5
    
    # Check sudo usage
    report "Recent sudo usage:"
    grep "sudo:" /var/log/auth.log 2>/dev/null | tail -n 5
    
    report ""
}

# Function to check installed packages
check_packages() {
    report "=== Package Security ==="
    report ""
    
    if [ -f /etc/debian_version ]; then
        # Check for known vulnerabilities
        if command -v debsecan &>/dev/null; then
            report "Known vulnerabilities:"
            debsecan
        fi
        
        # List installed packages
        report "Installed packages:"
        dpkg -l | grep ^ii
    elif [ -f /etc/redhat-release ]; then
        # Check for known vulnerabilities
        if command -v yum &>/dev/null; then
            report "Known vulnerabilities:"
            yum updateinfo list security
        fi
        
        # List installed packages
        report "Installed packages:"
        rpm -qa
    fi
    
    report ""
}

# Function to generate summary
generate_summary() {
    local issues=0
    
    report "=== Security Audit Summary ==="
    report "Timestamp: $(date)"
    report "Hostname: $(hostname)"
    report ""
    
    # Count security issues
    issues=$((issues + $(grep -c "WARNING:" "$REPORT_FILE")))
    
    report "Total security issues found: $issues"
    report ""
    
    # Send report by email if configured
    if [ -n "$EMAIL_RECIPIENT" ]; then
        mail -s "Security Audit Report - $(hostname)" "$EMAIL_RECIPIENT" < "$REPORT_FILE"
    fi
}

# Main execution
log "Starting security audit..."

# Check if running as root
check_root

# Initialize report
echo "Security Audit Report" > "$REPORT_FILE"
echo "===================" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Run security checks
check_updates
check_users
check_permissions
check_network
check_services
check_ssh
check_logs
check_packages

# Generate summary
generate_summary

log "Security audit completed. Report saved to: $REPORT_FILE" 