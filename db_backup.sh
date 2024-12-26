#!/bin/bash

# db_backup.sh - Database backup script
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/db_backup.conf"
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
: ${COMPRESS_BACKUPS:=true}
: ${PARALLEL_JOBS:=2}

# Logging setup
LOG_FILE="$LOG_DIR/db_backup_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_DIR"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check required tools
check_requirements() {
    local missing_tools=()
    
    # Check for general tools
    for tool in mysqldump pg_dump mongodump sqlite3 gzip; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log "Warning: Missing tools: ${missing_tools[*]}"
    fi
}

# Function to create backup directory structure
create_backup_structure() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/$timestamp"
    
    mkdir -p "$backup_path"/{mysql,postgresql,mongodb,sqlite}
    echo "$backup_path"
}

# Function to backup MySQL databases
backup_mysql() {
    local backup_path="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    if [ -n "$MYSQL_DBS" ] && command -v mysqldump &>/dev/null; then
        log "Starting MySQL backups..."
        
        # Export MySQL credentials to file
        if [ -n "$MYSQL_USER" ] && [ -n "$MYSQL_PASS" ]; then
            local mysql_cnf="/tmp/mysql_backup_${timestamp}.cnf"
            cat > "$mysql_cnf" <<EOF
[client]
user=$MYSQL_USER
password=$MYSQL_PASS
EOF
            chmod 600 "$mysql_cnf"
        fi
        
        for db in $MYSQL_DBS; do
            log "Backing up MySQL database: $db"
            local backup_file="$backup_path/mysql/${db}_${timestamp}.sql"
            
            if mysqldump --defaults-extra-file="$mysql_cnf" --single-transaction \
                        --quick --lock-tables=false "$db" > "$backup_file" 2>/dev/null; then
                log "MySQL backup completed: $db"
                if [ "$COMPRESS_BACKUPS" = true ]; then
                    gzip "$backup_file"
                fi
            else
                log "Failed to backup MySQL database: $db"
            fi
        done
        
        # Remove credentials file
        [ -f "$mysql_cnf" ] && rm "$mysql_cnf"
    fi
}

# Function to backup PostgreSQL databases
backup_postgresql() {
    local backup_path="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    if [ -n "$POSTGRES_DBS" ] && command -v pg_dump &>/dev/null; then
        log "Starting PostgreSQL backups..."
        
        # Export PostgreSQL credentials
        if [ -n "$POSTGRES_USER" ]; then
            export PGUSER="$POSTGRES_USER"
            export PGPASSWORD="$POSTGRES_PASS"
        fi
        
        for db in $POSTGRES_DBS; do
            log "Backing up PostgreSQL database: $db"
            local backup_file="$backup_path/postgresql/${db}_${timestamp}.sql"
            
            if pg_dump -Fc "$db" > "$backup_file" 2>/dev/null; then
                log "PostgreSQL backup completed: $db"
                if [ "$COMPRESS_BACKUPS" = true ]; then
                    gzip "$backup_file"
                fi
            else
                log "Failed to backup PostgreSQL database: $db"
            fi
        done
        
        # Clear credentials
        unset PGUSER PGPASSWORD
    fi
}

# Function to backup MongoDB databases
backup_mongodb() {
    local backup_path="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    if [ -n "$MONGO_DBS" ] && command -v mongodump &>/dev/null; then
        log "Starting MongoDB backups..."
        
        for db in $MONGO_DBS; do
            log "Backing up MongoDB database: $db"
            local backup_dir="$backup_path/mongodb/${db}_${timestamp}"
            
            if mongodump --uri="$MONGO_URI" --db="$db" --out="$backup_dir" &>/dev/null; then
                log "MongoDB backup completed: $db"
                if [ "$COMPRESS_BACKUPS" = true ]; then
                    tar -czf "${backup_dir}.tar.gz" -C "$backup_path/mongodb" "$(basename "$backup_dir")"
                    rm -rf "$backup_dir"
                fi
            else
                log "Failed to backup MongoDB database: $db"
            fi
        done
    fi
}

# Function to backup SQLite databases
backup_sqlite() {
    local backup_path="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    if [ -n "$SQLITE_DBS" ] && command -v sqlite3 &>/dev/null; then
        log "Starting SQLite backups..."
        
        for db_path in $SQLITE_DBS; do
            if [ -f "$db_path" ]; then
                log "Backing up SQLite database: $db_path"
                local db_name=$(basename "$db_path")
                local backup_file="$backup_path/sqlite/${db_name}_${timestamp}.sql"
                
                if sqlite3 "$db_path" ".backup '$backup_file'"; then
                    log "SQLite backup completed: $db_name"
                    if [ "$COMPRESS_BACKUPS" = true ]; then
                        gzip "$backup_file"
                    fi
                else
                    log "Failed to backup SQLite database: $db_path"
                fi
            else
                log "SQLite database not found: $db_path"
            fi
        done
    fi
}

# Function to verify backup integrity
verify_backup() {
    local file="$1"
    local type="$2"
    
    case "$type" in
        "mysql")
            if [ -f "$file" ]; then
                mysql --defaults-extra-file="$mysql_cnf" -e "SELECT 1;" &>/dev/null
                return $?
            fi
            ;;
        "postgresql")
            if [ -f "$file" ]; then
                pg_restore -l "$file" &>/dev/null
                return $?
            fi
            ;;
        "mongodb")
            if [ -f "$file" ]; then
                tar -tzf "$file" &>/dev/null
                return $?
            fi
            ;;
        "sqlite")
            if [ -f "$file" ]; then
                sqlite3 "$file" "PRAGMA integrity_check;" &>/dev/null
                return $?
            fi
            ;;
    esac
    return 1
}

# Function to clean old backups
clean_old_backups() {
    log "Cleaning old backups..."
    find "$BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -delete
    find "$BACKUP_DIR" -type d -empty -delete
}

# Function to sync to remote storage
sync_to_remote() {
    if [ -n "$REMOTE_PATH" ]; then
        log "Syncing backups to remote storage..."
        
        case "$REMOTE_TYPE" in
            "s3")
                if command -v aws &>/dev/null; then
                    aws s3 sync "$BACKUP_DIR" "$REMOTE_PATH"
                fi
                ;;
            "rsync")
                if command -v rsync &>/dev/null; then
                    rsync -avz --delete "$BACKUP_DIR/" "$REMOTE_PATH"
                fi
                ;;
            *)
                log "Unknown remote type: $REMOTE_TYPE"
                ;;
        esac
    fi
}

# Function to send notification
send_notification() {
    local status="$1"
    local message="$2"
    
    if [ -n "$EMAIL_RECIPIENT" ]; then
        echo "Database Backup $status
        
$message
        
Timestamp: $(date)
Host: $(hostname)
Log File: $LOG_FILE" | mail -s "Database Backup $status - $(hostname)" "$EMAIL_RECIPIENT"
    fi
}

# Main execution
log "Starting database backup process..."

# Check requirements
check_requirements

# Create backup directory structure
backup_path=$(create_backup_structure)

# Initialize error counter
errors=0

# Perform backups
backup_mysql "$backup_path" || ((errors++))
backup_postgresql "$backup_path" || ((errors++))
backup_mongodb "$backup_path" || ((errors++))
backup_sqlite "$backup_path" || ((errors++))

# Clean old backups
clean_old_backups

# Sync to remote storage
sync_to_remote

# Send notification
if [ "$errors" -eq 0 ]; then
    if [ "$SEND_NOTIFICATIONS" = true ]; then
        send_notification "Success" "All database backups completed successfully"
    fi
else
    if [ "$SEND_NOTIFICATIONS" = true ]; then
        send_notification "Warning" "Database backup completed with $errors errors"
    fi
fi

log "Database backup process completed with $errors errors" 