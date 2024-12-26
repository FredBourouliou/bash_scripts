#!/bin/bash

# file_search.sh - Advanced file search script
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/file_search.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Default values if not set in config
: ${SEARCH_DIR:="."}
: ${LOG_DIR:="./logs"}
: ${EXPORT_DIR:="./results"}
: ${MAX_DEPTH:="-1"}
: ${EXPORT_FORMAT:="csv"}

# Logging setup
LOG_FILE="$LOG_DIR/file_search_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")" "$EXPORT_DIR"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to print usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -n, --name PATTERN       Search by name pattern"
    echo "  -s, --size SIZE         Search by size (e.g., +10M, -1G)"
    echo "  -d, --date DAYS         Files modified in last N days"
    echo "  -c, --content PATTERN   Search file contents"
    echo "  -t, --type TYPE         File type (f:file, d:directory)"
    echo "  -x, --exclude PATTERN   Exclude pattern"
    echo "  -m, --maxdepth DEPTH    Maximum search depth"
    echo "  -f, --format FORMAT     Export format (csv,json)"
    echo "  -h, --help             Show this help"
    exit 1
}

# Function to build find command
build_find_command() {
    local cmd="find \"$SEARCH_DIR\""
    
    # Add maxdepth if specified
    if [ "$MAX_DEPTH" -ge 0 ]; then
        cmd="$cmd -maxdepth $MAX_DEPTH"
    fi
    
    # Add type if specified
    if [ -n "$FILE_TYPE" ]; then
        cmd="$cmd -type $FILE_TYPE"
    fi
    
    # Add name pattern if specified
    if [ -n "$NAME_PATTERN" ]; then
        cmd="$cmd -name \"$NAME_PATTERN\""
    fi
    
    # Add size if specified
    if [ -n "$SIZE_PATTERN" ]; then
        cmd="$cmd -size $SIZE_PATTERN"
    fi
    
    # Add date if specified
    if [ -n "$DATE_PATTERN" ]; then
        cmd="$cmd -mtime $DATE_PATTERN"
    fi
    
    # Add exclusions
    if [ -n "$EXCLUDE_PATTERN" ]; then
        for pattern in $EXCLUDE_PATTERN; do
            cmd="$cmd ! -path \"$pattern\""
        done
    fi
    
    echo "$cmd"
}

# Function to search file contents
search_content() {
    local pattern="$1"
    local files="$2"
    
    if [ -n "$pattern" ]; then
        echo "$files" | while read -r file; do
            if [ -f "$file" ] && grep -l "$pattern" "$file" 2>/dev/null; then
                echo "$file"
            fi
        done
    else
        echo "$files"
    fi
}

# Function to format file information
format_file_info() {
    local file="$1"
    local format="$2"
    local size
    local modified
    local type
    local perms
    
    size=$(stat -f %z "$file")
    modified=$(stat -f %Sm "$file")
    type=$(file -b "$file")
    perms=$(stat -f %Sp "$file")
    
    case "$format" in
        "csv")
            echo "\"$file\",\"$size\",\"$modified\",\"$type\",\"$perms\""
            ;;
        "json")
            echo "{\"path\":\"$file\",\"size\":$size,\"modified\":\"$modified\",\"type\":\"$type\",\"permissions\":\"$perms\"}"
            ;;
        *)
            echo "$file"
            ;;
    esac
}

# Function to export results
export_results() {
    local results="$1"
    local format="$2"
    local output_file="$EXPORT_DIR/search_results_$(date +%Y%m%d_%H%M%S)"
    
    case "$format" in
        "csv")
            output_file="$output_file.csv"
            echo "\"Path\",\"Size\",\"Modified\",\"Type\",\"Permissions\"" > "$output_file"
            echo "$results" | while read -r file; do
                format_file_info "$file" "csv" >> "$output_file"
            done
            ;;
        "json")
            output_file="$output_file.json"
            echo "[" > "$output_file"
            local first=true
            echo "$results" | while read -r file; do
                if [ "$first" = true ]; then
                    first=false
                else
                    echo "," >> "$output_file"
                fi
                format_file_info "$file" "json" >> "$output_file"
            done
            echo "]" >> "$output_file"
            ;;
    esac
    
    log "Results exported to: $output_file"
}

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -n|--name)
            NAME_PATTERN="$2"
            shift 2
            ;;
        -s|--size)
            SIZE_PATTERN="$2"
            shift 2
            ;;
        -d|--date)
            DATE_PATTERN="-$2"
            shift 2
            ;;
        -c|--content)
            CONTENT_PATTERN="$2"
            shift 2
            ;;
        -t|--type)
            FILE_TYPE="$2"
            shift 2
            ;;
        -x|--exclude)
            EXCLUDE_PATTERN="$2"
            shift 2
            ;;
        -m|--maxdepth)
            MAX_DEPTH="$2"
            shift 2
            ;;
        -f|--format)
            EXPORT_FORMAT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Main execution
log "Starting file search..."

# Build and execute find command
find_cmd=$(build_find_command)
log "Executing search command: $find_cmd"
results=$(eval "$find_cmd")

# Search content if specified
if [ -n "$CONTENT_PATTERN" ]; then
    log "Searching file contents for: $CONTENT_PATTERN"
    results=$(search_content "$CONTENT_PATTERN" "$results")
fi

# Export results
if [ -n "$results" ]; then
    export_results "$results" "$EXPORT_FORMAT"
else
    log "No results found"
fi

log "Search completed" 