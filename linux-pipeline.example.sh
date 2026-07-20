#!/bin/bash

MOVIE_NAME="$1"
PRESET="$2"

if [ -z "$MOVIE_NAME" ] || [ -z "$PRESET" ]; then
    echo "Usage: ./linux-pipeline.sh \"Movie Name (Year)\" \"Preset Name\""
    exit 1
fi

DISC_DRIVE="dev:0"
NAS_BASE="/path/to/NAS"
LOCAL_VIDEOS="$HOME/Videos"
WORK_DIR="$LOCAL_VIDEOS/$MOVIE_NAME"
RAW_MKV="$WORK_DIR/$MOVIE_NAME.mkv"
COMPRESSED_MKV="$LOCAL_VIDEOS/$MOVIE_NAME.mkv"
LOG_FILE="$LOCAL_VIDEOS/pipeline_queue.log"

echo "=== Starting Rip Pipeline for: $MOVIE_NAME ==="

# Step 1: MakeMKV Extraction
mkdir -p "$WORK_DIR"
echo "[1/2] Inspecting disc structure with MakeMKV..."

# Run 'info' command to check title count without ripping
DISC_INFO=$(makemkvcon -r info "$DISC_DRIVE" --minlength=3600)
TITLE_COUNT=$(echo "$DISC_INFO" | grep -c "^T:")

if [ "$TITLE_COUNT" -eq 0 ]; then
    echo "Error: No titles met the minimum length requirement (3600s)."
    exit 1
elif [ "$TITLE_COUNT" -gt 1 ]; then
    echo -e "\n=========================================================="
    echo -e "WARNING: Disc contains $TITLE_COUNT qualifying titles instead of 1!"
    echo -e "This disc may use playlist obfuscation or have a director's cut."
    echo -e "Pipeline halted before ripping. Manual investigation required."
    echo -e "=========================================================="
    exit 1
fi

echo "Disc verified (1 main title found). Ripping..."
mkdir -p "$WORK_DIR"

# Rip specifically the single identified title (Index 0)
makemkvcon mkv "$DISC_DRIVE" 0 "$WORK_DIR" | while read -r line; do
    echo "$line"
done

echo "[1/2] MakeMKV extraction complete."

# Step 2: Handle HandBrake Queueing
echo "[2/2] Checking HandBrake queue status..."

while pgrep -x "HandBrakeCLI" > /dev/null; do
    TIMESTAMP=$(date "+%Y-%m-%d %H:M:S")
    MSG="[$TIMESTAMP] HandBrake is busy. '$MOVIE_NAME' waiting in queue..."
    echo "$MSG"
    echo "$MSG" >> "$LOG_FILE"
    sleep 30
done

echo "HandBrake is free. Starting compression..."

HandBrakeCLI --input "$RAW_MKV" --output "$COMPRESSED_MKV" --preset "$PRESET" --optimize 2>&1 | while IFS= read -r line; do
    if [[ "$line" == *"Encoding: task"* ]]; then
        printf "\r%s   " "$line"
    else
        echo "$line"
    fi
done

echo -e "\n[2/2] Compression complete."

# Step 3: Size Evaluation & NAS Transfer
FILE_SIZE_BYTES=$(stat -c%s "$COMPRESSED_MKV" 2>/dev/null || stat -f%z "$COMPRESSED_MKV")
FILE_SIZE_GB=$(awk "BEGIN {print $FILE_SIZE_BYTES / 1024 / 1024 / 1024}")

echo "Compressed file size: $FILE_SIZE_GB GB"

PROCEED=true
GT_FOUR=$(awk "BEGIN {print ($FILE_SIZE_GB > 4.0) ? 1 : 0}")

if [ "$GT_FOUR" -eq 1 ]; then
    echo "Warning: File size exceeds 4 GB threshold."
    read -p "Proceed with NAS move? (y/n): " RESPONSE
    if [[ "$RESPONSE" != "y" && "$RESPONSE" != "Y" ]]; then
        PROCEED=false
        echo "NAS move aborted by user."
    fi
fi

if [ "$PROCEED" = true ]; then
    TARGET_DIR="$NAS_BASE/$MOVIE_NAME"
    mkdir -p "$TARGET_DIR"
    
    echo "Moving file to NAS..."
    mv "$COMPRESSED_MKV" "$TARGET_DIR/$MOVIE_NAME.mkv"
    rm -rf "$WORK_DIR"
    echo "Pipeline finished successfully!"
fi