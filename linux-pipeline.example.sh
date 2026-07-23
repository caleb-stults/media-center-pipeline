#!/usr/bin/env bash
set -euo pipefail

# Parameters & Argument Parsing
MOVIE_NAME=""
PRESET=""
BURN_SUBS=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --movie-name) MOVIE_NAME="$2"; shift ;;
        --preset) PRESET="$2"; shift ;;
        --burn-subs) BURN_SUBS=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [[ -z "$MOVIE_NAME" || -z "$PRESET" ]]; then
    echo "Error: --movie-name and --preset are mandatory."
    exit 1
fi

if [[ "$PRESET" != "Preset 1" && "$PRESET" != "Preset 2" && "$PRESET" != "Preset 3" ]]; then
    echo "Error: Preset must be 'Preset 1', 'Preset 2', or 'Preset 3'."
    exit 1
fi

# Configuration
DISC_DRIVE="disc:0"
NAS_BASE="/path/to/nas/movies"
LOCAL_VIDEOS="$HOME/Videos"
WORK_DIR="$LOCAL_VIDEOS/$MOVIE_NAME"
RAW_MKV="$WORK_DIR/$MOVIE_NAME.mkv"
COMPRESSED_MKV="$LOCAL_VIDEOS/$MOVIE_NAME.mkv"
LOG_FILE="$LOCAL_VIDEOS/pipeline_queue.log"
QUEUE_FILE="$LOCAL_VIDEOS/pipeline_queue.txt"

echo -e "\033[36mStarting Rip Pipeline for: $MOVIE_NAME\033[0m"

# Step 1: MakeMKV Extraction
mkdir -p "$WORK_DIR"

EXISTING_MKV_COUNT=$(find "$WORK_DIR" -maxdepth 1 -name "*.mkv" | wc -l)

if [[ "$EXISTING_MKV_COUNT" -gt 0 ]]; then
    echo -e "\033[33m[1/2] MKV files already exist in $WORK_DIR. Skipping MakeMKV extraction.\033[0m"
else
    echo -e "\033[33m[1/2] Ripping disc with MakeMKV...\033[0m"
    echo -e "\033[90m(MakeMKV will say 'Saving title' and wait here until the rip is finished)\033[0m"
    
    makemkvcon64 --minlength=3600 mkv "$DISC_DRIVE" all "$WORK_DIR"

    echo -e "\n\033[32m[1/2] MakeMKV extraction complete.\033[0m"

    EXTRACTED_FILES=("$WORK_DIR"/*.mkv)
    EXTRACTED_COUNT=${#EXTRACTED_FILES[@]}

    if [[ ! -f "${EXTRACTED_FILES[0]}" ]] || [[ "$EXTRACTED_COUNT" -eq 0 ]]; then
        echo -e "\033[31mError: No titles met the minimum length requirement (3600s).\033[0m"
        exit 1
    elif [[ "$EXTRACTED_COUNT" -gt 1 ]]; then
        echo -e "\033[31mWARNING: Detected $EXTRACTED_COUNT files instead of 1!\033[0m"
        echo -e "\033[33mThis disc uses playlist obfuscation or contains multiple cuts.\033[0m"
        echo -e "\033[33mWiping partial files and halting pipeline. Check source manually.\033[0m"
        rm -rf "$WORK_DIR"
        exit 1
    fi
fi

# Step 2: Handle HandBrake Queueing & Compression
echo -e "\033[33m[2/2] Checking HandBrake queue status...\033[0m"
echo -e "\033[36mRegistering '$MOVIE_NAME' in the encoding queue...\033[0m"

echo "$MOVIE_NAME" >> "$QUEUE_FILE"

while true; do
    if [[ -f "$QUEUE_FILE" ]]; then
        FIRST_LINE=$(grep -m 1 '^[[:space:]]*[^[:space:]]' "$QUEUE_FILE" || true)
        if [[ "$FIRST_LINE" == "$MOVIE_NAME" ]]; then
            echo -e "\033[32mStarting processing for '$MOVIE_NAME'...\033[0m"
            break
        fi
    fi
    echo -e "\033[33mAnother job is currently ahead in the queue. Waiting...\033[0m"
    sleep 30
done

while pgrep -x "HandBrakeCLI" > /dev/null; do
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    MSG="[$TIMESTAMP] HandBrake is currently busy processing another title. '$MOVIE_NAME' added to queue-wait state..."
    echo -e "\033[33m$MSG\033[0m"
    echo "$MSG" >> "$LOG_FILE"
    sleep 30
done

RAW_MKV_FILE=$(find "$WORK_DIR" -maxdepth 1 -name "*.mkv" | head -n 1)

if [[ -z "$RAW_MKV_FILE" ]]; then
    echo -e "\033[31mCRITICAL ERROR: No raw MKV file found in $WORK_DIR to compress!\033[0m"
    exit 1
fi

echo -e "\033[32mHandBrake is free. Starting compression...\033[0m"
HB_ARGS=(
    "--preset-import-gui"
    "--input" "$RAW_MKV_FILE"
    "--output" "$COMPRESSED_MKV"
    "--preset" "$PRESET"
    "--optimize"
)

if [[ "$BURN_SUBS" == true ]]; then
    echo -e "\033[33mSubtitle burn-in requested. Adding subtitle flags...\033[0m"
    HB_ARGS+=("--subtitle" "1" "--subtitle-burned" "1")
fi

HandBrakeCLI "${HB_ARGS[@]}" 2>&1 | while IFS= read -r line; do
    if [[ "$line" =~ "Encoding: task" ]]; then
        printf "\r%s   " "$line"
    else
        echo "$line"
    fi
done

HB_EXIT_CODE=${PIPESTATUS[0]}

if [[ "$HB_EXIT_CODE" -ne 0 ]]; then
    echo -e "\n\033[31mCRITICAL ERROR: HandBrake failed (Exit Code: $HB_EXIT_CODE).\033[0m"
    echo -e "\033[33mPreset '$PRESET' may be invalid or missing.\033[0m"
    echo -e "\033[33mYour raw MKV is safely preserved in: $WORK_DIR\033[0m"
    echo -e "\033[33mFix the issue and re-run. No re-rip necessary.\033[0m"
    exit 1
fi

echo -e "\n\033[32m[2/2] Compression complete.\033[0m"

# Step 3: Size Evaluation & NAS Transfer
FILE_SIZE_BYTES=$(stat -f%z "$COMPRESSED_MKV" 2>/dev/null || stat -c%s "$COMPRESSED_MKV" 2>/dev/null)
FILE_SIZE_GB=$(awk "BEGIN {print $FILE_SIZE_BYTES / 1073741824}")
ROUNDED_SIZE=$(awk "BEGIN {printf \"%.2f\", $FILE_SIZE_GB}")

echo -e "\033[36mCompressed file size: $ROUNDED_SIZE GB\033[0m"

PROCEED=true
OVER_LIMIT=$(awk "BEGIN {print ($FILE_SIZE_GB > 4.0) ? 1 : 0}")

if [[ "$OVER_LIMIT" -eq 1 ]]; then
    echo -e "\033[33mWarning: File size exceeds 4 GB threshold.\033[0m"
    read -p "Proceed with NAS move? (Y/N): " RESPONSE
    if [[ "$RESPONSE" != "Y" && "$RESPONSE" != "y" ]]; then
        PROCEED=false
        echo -e "\033[31mNAS move aborted by user. File remains in local Videos.\033[0m"
    fi
fi

if [[ "$PROCEED" == true ]]; then
    TARGET_DIR="$NAS_BASE/$MOVIE_NAME"
    mkdir -p "$TARGET_DIR"
    
    echo -e "\033[33mMoving file to NAS...\033[0m"
    mv -f "$COMPRESSED_MKV" "$TARGET_DIR/$MOVIE_NAME.mkv"

    if [[ -d "$WORK_DIR" ]]; then
        echo -e "\033[90mCleaning up temporary work directory...\033[0m"
        rm -rf "$WORK_DIR"
    fi

    if [[ -f "$QUEUE_FILE" ]]; then
        grep -v "^[[:space:]]*$" "$QUEUE_FILE" | grep -v "^$MOVIE_NAME$" > "${QUEUE_FILE}.tmp" || true
        if [[ -s "${QUEUE_FILE}.tmp" ]]; then
            mv "${QUEUE_FILE}.tmp" "$QUEUE_FILE"
            echo -e "\033[33mRemoved '$MOVIE_NAME' from queue. Handing off to next job...\033[0m"
        else
            rm -f "$QUEUE_FILE" "${QUEUE_FILE}.tmp"
            echo -e "\033[90mQueue is now empty. Cleaned up queue file.\033[0m"
        fi
    fi

    echo -e "\033[32mPipeline finished successfully! Directory state restored.\033[0m"
fi