#!/bin/bash

# Configuration
DISC_DRIVE="dev:0" # default device
NAS_BASE="/mnt/nas/Movies"
WORK_DIR="$HOME/Videos"
MOVIE_NAME=$1
PRESET=$2
SIZE_LIMIT=$((4 * 1024 * 1024 * 1024))

RAW_FOLDER="$WORK_DIR/$MOVIE_NAME"
RAW_MKV="$RAW_FOLDER/$MOVIE_NAME.mkv"
COMPRESSED_FILE="$WORK_DIR/$MOVIE_NAME.mkv"

# 1. MakeMKV
mkdir -p "$RAW_FOLDER"
makemkvcon mkv $DISC_DRIVE all "$RAW_FOLDER" --minlength=3600 --noscan

# 2. HandBrake
HandBrakeCLI -i "$RAW_MKV" -o "$COMPRESSED_FILE" --preset "$PRESET"

# 3. File Size Logic
FILE_SIZE=$(stat -c%s "$COMPRESSED_FILE")
PROCEED=false

if [ "$FILE_SIZE" -lt "$SIZE_LIMIT" ]; then
    echo "File size is under 4 GB. Auto-processing..."
    PROCEED=true
else
    read -p "File is over 4 GB. Proceed with move and cleanup? (y/n) " confirm
    if [[ $confirm == [yY] ]]; then PROCEED=true; fi
fi

# 4. Move and Cleanup
if [ "$PROCEED" = true ]; then
    TARGET_DIR="$NAS_BASE/$MOVIE_NAME"
    mkdir -p "$TARGET_DIR"
    mv "$COMPRESSED_FILE" "$TARGET_DIR/$MOVIE_NAME.mkv"
    rm -rf "$RAW_FOLDER"
    echo "Process complete."
else
    echo "Process aborted."
fi