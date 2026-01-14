#!/bin/bash

# V11S
# ./script/convert/convert-ts-to-mp4.sh '/Volumes/V11S Pro/Video' '/Volumes/CameraUploads/V11SPro'

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Pipestatus to fail if any command in a pipeline fails
set -o pipefail

# Enable case-insensitive globbing and matching
shopt -s nocasematch

# --- Configuration ---
# FFMPEG options for converting TS to MP4
# -c copy: Copies video and audio streams without re-encoding (fast, preserves quality)
# -map_metadata 0: Copies global metadata from the input file to the output file
# -movflags use_metadata_tags: Ensures metadata tags (like creation time if present) are written
FFMPEG_OPTS="-c copy -map_metadata 0 -movflags use_metadata_tags"

# --- Functions ---
log_info() {
    echo "[INFO] $1"
}

log_warn() {
    echo "[WARN] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

# --- Script Start ---

# Check for required command: ffmpeg
if ! command -v ffmpeg &> /dev/null; then
    log_error "ffmpeg could not be found. Please install ffmpeg to use this script."
    log_error "On macOS, you can install it using Homebrew: brew install ffmpeg"
    exit 1
fi

# Check for correct number of arguments
if [ "$#" -ne 2 ]; then
    log_error "Usage: $0 <input_directory> <output_directory>"
    echo "Example: $0 /path/to/source_files /path/to/destination_files"
    exit 1
fi

INPUT_DIR="$1"
OUTPUT_DIR="$2"

# Validate input directory
if [ ! -d "$INPUT_DIR" ]; then
    log_error "Input directory '$INPUT_DIR' not found or is not a directory."
    exit 1
fi

# Create output directory if it doesn't exist
if [ ! -d "$OUTPUT_DIR" ]; then
    log_info "Output directory '$OUTPUT_DIR' does not exist. Creating it..."
    mkdir -p "$OUTPUT_DIR"
    if [ $? -ne 0 ]; then
        log_error "Failed to create output directory '$OUTPUT_DIR'."
        exit 1
    fi
fi

# Remove trailing slash from input dir path for consistent relative path calculation
INPUT_DIR_CLEAN="${INPUT_DIR%/}"

log_info "Starting file processing..."
log_info "Input directory: $INPUT_DIR_CLEAN"
log_info "Output directory: $OUTPUT_DIR"

# Find all files (jpg, jpeg, ts, mp4) in the input directory recursively
# -print0 and read -d $'\0' handle filenames with spaces, newlines, or other special characters
find "$INPUT_DIR_CLEAN" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.ts" -o -iname "*.mp4" -o -iname "*.lrf" \) -print0 | while IFS= read -r -d $'\0' SOURCE_FILE_PATH; do
    # Get the path of the file relative to the input directory
    # Example: if INPUT_DIR_CLEAN="/input" and SOURCE_FILE_PATH="/input/subdir/file.txt",
    # then RELATIVE_FILE_PATH="subdir/file.txt"
    RELATIVE_FILE_PATH="${SOURCE_FILE_PATH#$INPUT_DIR_CLEAN/}"

    # Determine the full path for the destination file/directory
    DEST_SUBDIR="$OUTPUT_DIR/$(dirname "$RELATIVE_FILE_PATH")"
    
    # Create the corresponding subdirectory structure in the output directory
    mkdir -p "$DEST_SUBDIR"
    if [ $? -ne 0 ]; then
        log_warn "Could not create subdirectory '$DEST_SUBDIR'. Skipping file '$SOURCE_FILE_PATH'."
        continue
    fi

    FILENAME=$(basename "$SOURCE_FILE_PATH")
    EXTENSION="${FILENAME##*.}"
    BASENAME_NO_EXT="${FILENAME%.*}"

    if [[ "$EXTENSION" == "jpg" || "$EXTENSION" == "jpeg" ]]; then
        DEST_FILE_PATH="$DEST_SUBDIR/$FILENAME"
        if [ -f "$DEST_FILE_PATH" ]; then
            log_info "Image '$DEST_FILE_PATH' already exists. Skipping and removing source."
            rm "$SOURCE_FILE_PATH"
        else
            log_info "Copying image: '$SOURCE_FILE_PATH' to '$DEST_FILE_PATH'"
            cp -p "$SOURCE_FILE_PATH" "$DEST_FILE_PATH"
            if [ $? -eq 0 ]; then
                rm "$SOURCE_FILE_PATH"
                log_info "Successfully copied and removed '$SOURCE_FILE_PATH'"
            else
                log_warn "Failed to copy '$SOURCE_FILE_PATH'."
            fi
        fi
    elif [[ "$EXTENSION" == "ts" ]]; then
        DEST_MP4_PATH="$DEST_SUBDIR/$BASENAME_NO_EXT.mp4"
        if [ -f "$DEST_MP4_PATH" ]; then
            log_info "Video '$DEST_MP4_PATH' (from TS) already exists. Skipping and removing source."
            rm "$SOURCE_FILE_PATH"
        else
            log_info "Converting TS to MP4: '$SOURCE_FILE_PATH' to '$DEST_MP4_PATH'"
            if ffmpeg -i "$SOURCE_FILE_PATH" $FFMPEG_OPTS "$DEST_MP4_PATH" </dev/null >/dev/null 2>&1; then
                touch -r "$SOURCE_FILE_PATH" "$DEST_MP4_PATH"
                log_info "Successfully converted and set timestamp for '$DEST_MP4_PATH'"
                rm "$SOURCE_FILE_PATH"
                log_info "Successfully removed original TS file '$SOURCE_FILE_PATH'"
            else
                log_warn "ffmpeg conversion failed for '$SOURCE_FILE_PATH'."
            fi
        fi
    elif [[ "$EXTENSION" == "mp4" ]]; then
        DEST_FILE_PATH="$DEST_SUBDIR/$FILENAME"
        if [ -f "$DEST_FILE_PATH" ]; then
            log_info "MP4 file '$DEST_FILE_PATH' already exists. Skipping and removing source."
            rm "$SOURCE_FILE_PATH"
        else
            log_info "Moving MP4 file: '$SOURCE_FILE_PATH' to '$DEST_FILE_PATH'"
            if cp -p "$SOURCE_FILE_PATH" "$DEST_FILE_PATH"; then
                rm "$SOURCE_FILE_PATH"
                log_info "Successfully moved '$SOURCE_FILE_PATH' to '$DEST_FILE_PATH'"
            else
                log_warn "Failed to copy '$SOURCE_FILE_PATH' to '$DEST_FILE_PATH'. Original file not removed."
            fi
        fi
    elif [[ "$EXTENSION" == "lrf" || "$EXTENSION" == "LRF" ]]; then
        DEST_FILE_PATH="$DEST_SUBDIR/$FILENAME"
        if [ -f "$DEST_FILE_PATH" ]; then
            log_info "LRF file '$DEST_FILE_PATH' already exists. Skipping and removing source."
            rm "$SOURCE_FILE_PATH"
        else
            log_info "Moving LRF file: '$SOURCE_FILE_PATH' to '$DEST_FILE_PATH'"
            if cp -p "$SOURCE_FILE_PATH" "$DEST_FILE_PATH"; then
                rm "$SOURCE_FILE_PATH"
                log_info "Successfully moved '$SOURCE_FILE_PATH' to '$DEST_FILE_PATH'"
            else
                log_warn "Failed to copy '$SOURCE_FILE_PATH' to '$DEST_FILE_PATH'. Original file not removed."
            fi
        fi
    else
        # This case should not be reached due to the find command's filtering,
        # but it's here for robustness.
        log_warn "Skipping unsupported file type: '$SOURCE_FILE_PATH'"
    fi
done

shopt -u nocasematch # Disable case-insensitive matching

log_info "Processing complete."
exit 0