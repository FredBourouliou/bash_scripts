#!/bin/bash

# web_deploy.sh - Web application deployment automation script
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/web_deploy.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Default values if not set in config
: ${DEPLOY_DIR:="/var/www/html"}
: ${GIT_REPO:=""}
: ${GIT_BRANCH:="main"}
: ${BACKUP_DIR:="./backups"}
: ${COMPOSER_INSTALL:=false}
: ${NPM_INSTALL:=false}
: ${ARTISAN_MIGRATE:=false}
: ${CACHE_CLEAR:=false}

# Logging setup
LOG_FILE="./logs/web_deploy_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to backup current deployment
backup_current() {
    if [ -d "$DEPLOY_DIR" ]; then
        backup_name="$(basename "$DEPLOY_DIR")_$(date +%Y%m%d_%H%M%S).tar.gz"
        log "Creating backup: $backup_name"
        mkdir -p "$BACKUP_DIR"
        if tar -czf "$BACKUP_DIR/$backup_name" -C "$(dirname "$DEPLOY_DIR")" "$(basename "$DEPLOY_DIR")"; then
            log "Backup created successfully"
        else
            log "Backup failed"
            exit 1
        fi
    fi
}

# Function to update from git
update_from_git() {
    if [ -z "$GIT_REPO" ]; then
        log "No Git repository configured"
        return 1
    fi

    if [ ! -d "$DEPLOY_DIR/.git" ]; then
        log "Cloning repository..."
        git clone -b "$GIT_BRANCH" "$GIT_REPO" "$DEPLOY_DIR"
    else
        log "Updating repository..."
        cd "$DEPLOY_DIR" || exit 1
        git fetch origin
        git reset --hard "origin/$GIT_BRANCH"
    fi
}

# Function to install dependencies
install_dependencies() {
    cd "$DEPLOY_DIR" || exit 1

    if [ "$COMPOSER_INSTALL" = true ] && [ -f "composer.json" ]; then
        log "Installing Composer dependencies..."
        composer install --no-dev --optimize-autoloader
    fi

    if [ "$NPM_INSTALL" = true ] && [ -f "package.json" ]; then
        log "Installing NPM dependencies..."
        npm install --production
        if [ "$NPM_BUILD" = true ]; then
            log "Building assets..."
            npm run build
        fi
    fi
}

# Function to run Laravel-specific tasks
laravel_tasks() {
    if [ "$ARTISAN_MIGRATE" = true ] && [ -f "artisan" ]; then
        log "Running database migrations..."
        php artisan migrate --force
    fi

    if [ "$CACHE_CLEAR" = true ] && [ -f "artisan" ]; then
        log "Clearing application cache..."
        php artisan cache:clear
        php artisan config:clear
        php artisan route:clear
        php artisan view:clear
    fi
}

# Function to set permissions
set_permissions() {
    if [ -n "$WEB_USER" ] && [ -n "$WEB_GROUP" ]; then
        log "Setting permissions..."
        chown -R "$WEB_USER:$WEB_GROUP" "$DEPLOY_DIR"
        find "$DEPLOY_DIR" -type f -exec chmod 644 {} \;
        find "$DEPLOY_DIR" -type d -exec chmod 755 {} \;
    fi
}

# Function to run post-deploy hooks
run_post_deploy_hooks() {
    if [ -n "$POST_DEPLOY_SCRIPT" ] && [ -f "$POST_DEPLOY_SCRIPT" ]; then
        log "Running post-deploy script..."
        bash "$POST_DEPLOY_SCRIPT"
    fi
}

# Main execution
log "Starting deployment process..."

# Create backup
backup_current

# Update from Git
if ! update_from_git; then
    log "Deployment failed at git update stage"
    exit 1
fi

# Install dependencies
install_dependencies

# Run Laravel tasks
laravel_tasks

# Set permissions
set_permissions

# Run post-deploy hooks
run_post_deploy_hooks

log "Deployment completed successfully" 