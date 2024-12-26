#!/bin/bash

# backup.sh - Automated backup script for directories and databases
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/backup.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Default values if not set in config
: ${BACKUP_DIR:="./backups"}
: ${LOG_DIR:="./logs"}
: ${RETENTION_DAYS:=30}
: ${REMOTE_HOST:=""}
: ${REMOTE_PATH:=""}
: ${MYSQL_DBS:=""}
: ${POSTGRES_DBS:=""}

# Ensure required directories exist
mkdir -p "$BACKUP_DIR" "$LOG_DIR"

# Logging setup
LOG_FILE="$LOG_DIR/backup_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to backup MySQL databases
backup_mysql() {
    if [ -n "$MYSQL_DBS" ]; then
        log "Starting MySQL backup..."
        for db in $MYSQL_DBS; do
            backup_file="$BACKUP_DIR/mysql_${db}_$(date +%Y%m%d_%H%M%S).sql.gz"
            if mysqldump -u "$MYSQL_USER" -p"$MYSQL_PASS" "$db" | gzip > "$backup_file"; then
                log "MySQL backup completed for $db"
            else
                log "Error backing up MySQL database: $db"
            fi
        done
    fi
}

# Function to backup PostgreSQL databases
backup_postgres() {
    if [ -n "$POSTGRES_DBS" ]; then
        log "Starting PostgreSQL backup..."
        for db in $POSTGRES_DBS; do
            backup_file="$BACKUP_DIR/postgres_${db}_$(date +%Y%m%d_%H%M%S).sql.gz"
            if PGPASSWORD="$POSTGRES_PASS" pg_dump -U "$POSTGRES_USER" "$db" | gzip > "$backup_file"; then
                log "PostgreSQL backup completed for $db"
            else
                log "Error backing up PostgreSQL database: $db"
            fi
        done
    fi
}

# Function to backup directories
backup_directories() {
    if [ -n "$BACKUP_DIRS" ]; then
        log "Starting directory backup..."
        for dir in $BACKUP_DIRS; do
            backup_name=$(basename "$dir")
            backup_file="$BACKUP_DIR/${backup_name}_$(date +%Y%m%d_%H%M%S).tar.gz"
            if tar -czf "$backup_file" "$dir"; then
                log "Directory backup completed for $dir"
            else
                log "Error backing up directory: $dir"
            fi
        done
    fi
}

# Function to sync to remote server
sync_to_remote() {
    if [ -n "$REMOTE_HOST" ] && [ -n "$REMOTE_PATH" ]; then
        log "Syncing backups to remote server..."
        if rsync -avz --delete "$BACKUP_DIR/" "$REMOTE_HOST:$REMOTE_PATH"; then
            log "Remote sync completed"
        else
            log "Error syncing to remote server"
        fi
    fi
}

# Function to clean old backups
cleanup_old_backups() {
    log "Cleaning up old backups..."
    find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete
    log "Cleanup completed"
}

# Main execution
log "Starting backup process..."

# Run backups
backup_mysql
backup_postgres
backup_directories

# Sync to remote if configured
sync_to_remote

# Cleanup old backups
cleanup_old_backups

log "Backup process completed" 