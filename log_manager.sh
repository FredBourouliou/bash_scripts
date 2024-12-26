#!/bin/bash

# log_manager.sh - Log management script
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/log_manager.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Default values if not set in config
: ${LOG_DIR:="./logs"}
: ${ARCHIVE_DIR:="./archives"}
: ${RETENTION_DAYS:=30}
: ${COMPRESS_LOGS:=true}
: ${MAX_LOG_SIZE:=100}  # MB

# Logging setup
LOG_FILE="$LOG_DIR/log_manager_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")" "$ARCHIVE_DIR"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to get file size in MB
get_file_size() {
    local file="$1"
    local size
    
    if [ -f "$file" ]; then
        size=$(stat -f %z "$file" 2>/dev/null || stat -c %s "$file" 2>/dev/null)
        echo "$((size / 1024 / 1024))"
    else
        echo "0"
    fi
}

# Function to compress log file
compress_log() {
    local file="$1"
    local compressed_file="${file}.gz"
    
    if [ -f "$file" ] && ! [[ "$file" =~ \.gz$ ]]; then
        if gzip -c "$file" > "$compressed_file"; then
            rm "$file"
            log "Compressed: $file"
            return 0
        else
            log "Failed to compress: $file"
            return 1
        fi
    fi
    return 0
}

# Function to rotate log file
rotate_log() {
    local file="$1"
    local max_rotations="${2:-5}"
    
    # Remove oldest rotation if it exists
    if [ -f "${file}.${max_rotations}" ]; then
        rm "${file}.${max_rotations}"
    fi
    
    # Rotate existing logs
    for i in $(seq $((max_rotations - 1)) -1 1); do
        if [ -f "${file}.$i" ]; then
            mv "${file}.$i" "${file}.$((i + 1))"
        fi
    done
    
    # Create new rotation
    if [ -f "$file" ]; then
        cp "$file" "${file}.1"
        : > "$file"
        log "Rotated: $file"
    fi
}

# Function to archive old logs
archive_logs() {
    local source_dir="$1"
    local pattern="$2"
    
    find "$source_dir" -type f -name "$pattern" -mtime +"$RETENTION_DAYS" | while read -r file; do
        if [ -f "$file" ]; then
            local archive_path="$ARCHIVE_DIR/$(basename "$file")_$(date +%Y%m%d_%H%M%S)"
            
            if mv "$file" "$archive_path"; then
                log "Archived: $file -> $archive_path"
                if [ "$COMPRESS_LOGS" = true ]; then
                    compress_log "$archive_path"
                fi
            else
                log "Failed to archive: $file"
            fi
        fi
    done
}

# Function to clean old archives
clean_old_archives() {
    if [ -n "$ARCHIVE_RETENTION" ]; then
        log "Cleaning old archives..."
        find "$ARCHIVE_DIR" -type f -mtime +"$ARCHIVE_RETENTION" -delete
        find "$ARCHIVE_DIR" -type d -empty -delete
    fi
}

# Function to check log sizes
check_log_sizes() {
    local dir="$1"
    local pattern="$2"
    
    find "$dir" -type f -name "$pattern" | while read -r file; do
        local size
        size=$(get_file_size "$file")
        
        if [ "$size" -gt "$MAX_LOG_SIZE" ]; then
            log "Log file exceeds maximum size: $file ($size MB)"
            rotate_log "$file"
        fi
    done
}

# Function to analyze log content
analyze_logs() {
    local file="$1"
    local output_file="$ARCHIVE_DIR/analysis_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Log Analysis Report"
        echo "==================="
        echo "File: $file"
        echo "Date: $(date)"
        echo
        
        echo "Top IP Addresses:"
        grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" "$file" 2>/dev/null | sort | uniq -c | sort -rn | head -10
        echo
        
        echo "HTTP Status Codes:"
        grep -oE "HTTP/[0-9.]+ [0-9]+" "$file" 2>/dev/null | sort | uniq -c | sort -rn
        echo
        
        echo "Top URLs:"
        grep -oE "GET .* HTTP" "$file" 2>/dev/null | sort | uniq -c | sort -rn | head -10
        echo
        
        echo "Error Messages:"
        grep -i "error\|failed\|failure" "$file" 2>/dev/null | sort | uniq -c | sort -rn | head -10
        echo
        
        echo "Access Times:"
        grep -oE "[0-9]{2}:[0-9]{2}:[0-9]{2}" "$file" 2>/dev/null | 
        awk '{h=substr($1,1,2); count[h]++} END {for (h in count) print h":00",count[h]}' | sort
        
    } > "$output_file"
    
    log "Analysis completed: $output_file"
}

# Function to send report
send_report() {
    if [ "$SEND_REPORT" = true ] && [ -n "$EMAIL_RECIPIENT" ]; then
        local report_file="$ARCHIVE_DIR/log_report_$(date +%Y%m%d).txt"
        
        {
            echo "Log Management Report"
            echo "===================="
            echo "Date: $(date)"
            echo "Host: $(hostname)"
            echo
            
            echo "Managed Directories:"
            for dir in $LOG_DIRS; do
                echo "- $dir"
                echo "  Files: $(find "$dir" -type f | wc -l)"
                echo "  Total Size: $(du -sh "$dir" 2>/dev/null | cut -f1)"
            done
            echo
            
            echo "Archive Status:"
            echo "- Location: $ARCHIVE_DIR"
            echo "- Files: $(find "$ARCHIVE_DIR" -type f | wc -l)"
            echo "- Total Size: $(du -sh "$ARCHIVE_DIR" 2>/dev/null | cut -f1)"
            echo
            
            echo "Recent Actions:"
            tail -n 50 "$LOG_FILE"
            
        } > "$report_file"
        
        mail -s "Log Management Report - $(hostname)" "$EMAIL_RECIPIENT" < "$report_file"
    fi
}

# Main execution
log "Starting log management process..."

# Process each log directory
for dir in $LOG_DIRS; do
    if [ -d "$dir" ]; then
        log "Processing directory: $dir"
        
        # Process each pattern
        for pattern in $LOG_PATTERNS; do
            # Check log sizes and rotate if needed
            check_log_sizes "$dir" "$pattern"
            
            # Archive old logs
            archive_logs "$dir" "$pattern"
            
            # Analyze logs if enabled
            if [ "$ANALYZE_LOGS" = true ]; then
                find "$dir" -type f -name "$pattern" -mtime -1 | while read -r file; do
                    analyze_logs "$file"
                done
            fi
        done
    else
        log "Directory not found: $dir"
    fi
done

# Clean old archives
clean_old_archives

# Send report
send_report

log "Log management process completed" 