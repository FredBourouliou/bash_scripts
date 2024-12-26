#!/bin/bash

# media_processor.sh - Media processing script for images and videos
# Author: Frederic Bourouliou
# Version: 1.0

# Source configuration
CONFIG_FILE="config/media_processor.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Default values if not set in config
: ${INPUT_DIR:="./input"}
: ${OUTPUT_DIR:="./output"}
: ${LOG_DIR:="./logs"}
: ${TEMP_DIR:="./temp"}
: ${IMAGE_FORMATS:="jpg jpeg png gif webp"}
: ${VIDEO_FORMATS:="mp4 avi mkv mov"}
: ${MAX_PROCESSES:=4}

# Logging setup
LOG_FILE="$LOG_DIR/media_processor_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")" "$OUTPUT_DIR" "$TEMP_DIR"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check required tools
check_requirements() {
    local missing_tools=()
    
    # Check for ImageMagick
    if ! command -v convert &>/dev/null; then
        missing_tools+=("ImageMagick")
    fi
    
    # Check for FFmpeg
    if ! command -v ffmpeg &>/dev/null; then
        missing_tools+=("FFmpeg")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log "Error: Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
}

# Function to process image
process_image() {
    local input="$1"
    local output_dir="$2"
    local filename
    filename=$(basename "$input")
    local base="${filename%.*}"
    local ext="${filename##*.}"
    local output
    
    case "$IMAGE_OPERATION" in
        "resize")
            output="$output_dir/${base}_${IMAGE_SIZE}.${ext}"
            if convert "$input" -resize "$IMAGE_SIZE" "$output"; then
                log "Resized image: $input -> $output"
                return 0
            fi
            ;;
        "compress")
            output="$output_dir/${base}_compressed.${ext}"
            if convert "$input" -quality "$IMAGE_QUALITY" "$output"; then
                log "Compressed image: $input -> $output"
                return 0
            fi
            ;;
        "convert")
            output="$output_dir/${base}.${IMAGE_TARGET_FORMAT}"
            if convert "$input" "$output"; then
                log "Converted image: $input -> $output"
                return 0
            fi
            ;;
        "watermark")
            if [ -f "$WATERMARK_IMAGE" ]; then
                output="$output_dir/${base}_watermarked.${ext}"
                if composite -gravity center -dissolve "$WATERMARK_OPACITY" "$WATERMARK_IMAGE" "$input" "$output"; then
                    log "Added watermark: $input -> $output"
                    return 0
                fi
            else
                log "Error: Watermark image not found: $WATERMARK_IMAGE"
            fi
            ;;
        *)
            log "Error: Unknown image operation: $IMAGE_OPERATION"
            ;;
    esac
    
    log "Error processing image: $input"
    return 1
}

# Function to process video
process_video() {
    local input="$1"
    local output_dir="$2"
    local filename
    filename=$(basename "$input")
    local base="${filename%.*}"
    local ext="${filename##*.}"
    local output
    
    case "$VIDEO_OPERATION" in
        "compress")
            output="$output_dir/${base}_compressed.${ext}"
            if ffmpeg -i "$input" -c:v libx264 -crf "$VIDEO_QUALITY" -c:a aac "$output" -y; then
                log "Compressed video: $input -> $output"
                return 0
            fi
            ;;
        "convert")
            output="$output_dir/${base}.${VIDEO_TARGET_FORMAT}"
            if ffmpeg -i "$input" "$output" -y; then
                log "Converted video: $input -> $output"
                return 0
            fi
            ;;
        "resize")
            output="$output_dir/${base}_${VIDEO_SIZE}.${ext}"
            if ffmpeg -i "$input" -vf "scale=$VIDEO_SIZE" -c:a copy "$output" -y; then
                log "Resized video: $input -> $output"
                return 0
            fi
            ;;
        "extract-audio")
            output="$output_dir/${base}.mp3"
            if ffmpeg -i "$input" -vn -acodec libmp3lame -q:a 2 "$output" -y; then
                log "Extracted audio: $input -> $output"
                return 0
            fi
            ;;
        *)
            log "Error: Unknown video operation: $VIDEO_OPERATION"
            ;;
    esac
    
    log "Error processing video: $input"
    return 1
}

# Function to process files in parallel
process_files() {
    local file_type="$1"
    local extensions=()
    local pids=()
    
    # Get list of extensions based on file type
    if [ "$file_type" = "image" ]; then
        IFS=' ' read -r -a extensions <<< "$IMAGE_FORMATS"
    else
        IFS=' ' read -r -a extensions <<< "$VIDEO_FORMATS"
    fi
    
    # Process each file
    for ext in "${extensions[@]}"; do
        find "$INPUT_DIR" -type f -iname "*.${ext}" | while read -r file; do
            # Wait if we have too many processes
            while [ ${#pids[@]} -ge "$MAX_PROCESSES" ]; do
                for pid in "${pids[@]}"; do
                    if ! kill -0 "$pid" 2>/dev/null; then
                        pids=("${pids[@]/$pid}")
                    fi
                done
                sleep 1
            done
            
            # Process file in background
            if [ "$file_type" = "image" ]; then
                process_image "$file" "$OUTPUT_DIR" &
            else
                process_video "$file" "$OUTPUT_DIR" &
            fi
            pids+=($!)
        done
    done
    
    # Wait for all processes to complete
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

# Function to clean temporary files
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        log "Cleaning up temporary files..."
        rm -rf "${TEMP_DIR:?}"/*
    fi
}

# Main execution
log "Starting media processing..."

# Check requirements
check_requirements

# Process images if enabled
if [ "$PROCESS_IMAGES" = true ]; then
    log "Processing images..."
    process_files "image"
fi

# Process videos if enabled
if [ "$PROCESS_VIDEOS" = true ]; then
    log "Processing videos..."
    process_files "video"
fi

# Cleanup
cleanup

log "Media processing completed successfully" 