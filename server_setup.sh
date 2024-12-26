#!/bin/bash

# server_setup.sh - Initial server configuration script
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/server_setup.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Logging setup
LOG_FILE="./logs/server_setup_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if running as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        log "Error: This script must be run as root"
        exit 1
    fi
}

# Function to update system packages
update_system() {
    log "Updating system packages..."
    if [ -f /etc/debian_version ]; then
        apt-get update
        apt-get upgrade -y
    elif [ -f /etc/redhat-release ]; then
        yum update -y
    fi
}

# Function to install essential packages
install_essentials() {
    log "Installing essential packages..."
    if [ -f /etc/debian_version ]; then
        apt-get install -y $ESSENTIAL_PACKAGES
    elif [ -f /etc/redhat-release ]; then
        yum install -y $ESSENTIAL_PACKAGES
    fi
}

# Function to configure timezone
configure_timezone() {
    if [ -n "$TIMEZONE" ]; then
        log "Setting timezone to $TIMEZONE..."
        timedatectl set-timezone "$TIMEZONE"
    fi
}

# Function to configure hostname
configure_hostname() {
    if [ -n "$HOSTNAME" ]; then
        log "Setting hostname to $HOSTNAME..."
        hostnamectl set-hostname "$HOSTNAME"
        echo "127.0.0.1 $HOSTNAME" >> /etc/hosts
    fi
}

# Function to create users
create_users() {
    if [ -n "$USERS" ]; then
        log "Creating users..."
        while IFS=: read -r username password groups; do
            if ! id "$username" &>/dev/null; then
                useradd -m -s /bin/bash "$username"
                echo "$username:$password" | chpasswd
                if [ -n "$groups" ]; then
                    usermod -aG "$groups" "$username"
                fi
                log "Created user: $username"
            fi
        done <<< "$USERS"
    fi
}

# Function to configure SSH
configure_ssh() {
    log "Configuring SSH..."
    if [ -f "/etc/ssh/sshd_config" ]; then
        # Backup original config
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
        
        # Apply SSH configurations
        if [ "$SSH_DISABLE_ROOT" = true ]; then
            sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
        fi
        if [ "$SSH_DISABLE_PASSWORD_AUTH" = true ]; then
            sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
        fi
        if [ -n "$SSH_PORT" ]; then
            sed -i "s/^#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
        fi
        
        # Restart SSH service
        systemctl restart sshd
    fi
}

# Function to configure firewall
configure_firewall() {
    log "Configuring firewall..."
    if command -v ufw &>/dev/null; then
        ufw --force reset
        ufw default deny incoming
        ufw default allow outgoing
        
        # Allow SSH
        if [ -n "$SSH_PORT" ]; then
            ufw allow "$SSH_PORT/tcp" comment "SSH"
        else
            ufw allow 22/tcp comment "SSH"
        fi
        
        # Allow additional ports
        if [ -n "$FIREWALL_ALLOW_PORTS" ]; then
            for port in $FIREWALL_ALLOW_PORTS; do
                ufw allow "$port" comment "Custom allowed port"
            done
        fi
        
        ufw --force enable
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --zone=public --permanent --remove-service=ssh
        
        # Allow SSH
        if [ -n "$SSH_PORT" ]; then
            firewall-cmd --zone=public --permanent --add-port="$SSH_PORT/tcp"
        else
            firewall-cmd --zone=public --permanent --add-port=22/tcp
        fi
        
        # Allow additional ports
        if [ -n "$FIREWALL_ALLOW_PORTS" ]; then
            for port in $FIREWALL_ALLOW_PORTS; do
                firewall-cmd --zone=public --permanent --add-port="$port"
            done
        fi
        
        firewall-cmd --reload
    fi
}

# Function to configure fail2ban
configure_fail2ban() {
    if [ "$INSTALL_FAIL2BAN" = true ]; then
        log "Configuring fail2ban..."
        if [ -f /etc/debian_version ]; then
            apt-get install -y fail2ban
        elif [ -f /etc/redhat-release ]; then
            yum install -y fail2ban
        fi
        
        # Configure fail2ban
        cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
        systemctl enable fail2ban
        systemctl start fail2ban
    fi
}

# Function to setup automatic updates
setup_automatic_updates() {
    if [ "$ENABLE_AUTO_UPDATES" = true ]; then
        log "Setting up automatic updates..."
        if [ -f /etc/debian_version ]; then
            apt-get install -y unattended-upgrades
            dpkg-reconfigure -plow unattended-upgrades
        elif [ -f /etc/redhat-release ]; then
            yum install -y yum-cron
            systemctl enable yum-cron
            systemctl start yum-cron
        fi
    fi
}

# Function to configure basic monitoring
setup_monitoring() {
    if [ "$INSTALL_MONITORING" = true ]; then
        log "Setting up basic monitoring..."
        if [ -f /etc/debian_version ]; then
            apt-get install -y htop iotop iftop
        elif [ -f /etc/redhat-release ]; then
            yum install -y htop iotop iftop
        fi
    fi
}

# Main execution
log "Starting server setup..."

# Check if running as root
check_root

# Update system
update_system

# Install essential packages
install_essentials

# Configure basic settings
configure_timezone
configure_hostname

# Create users
create_users

# Configure services
configure_ssh
configure_firewall
configure_fail2ban

# Setup additional features
setup_automatic_updates
setup_monitoring

log "Server setup completed successfully" 