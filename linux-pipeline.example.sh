#!/usr/bin/env bash

MovieName="$1"
Preset="$2"
BurnSubs=false

# Check if the optional third argument is the subtitle flag
if [ "$3" = "--burn-subs" ]; then
    BurnSubs=true
fi

# Basic validation to make sure required arguments were passed
if [ -z "$MovieName" ] || [ -z "$Preset" ]; then
    echo "Error: Missing required arguments."
    echo "Usage: ./linux-pipeline.sh \"Movie Name\" \"Preset Name\" [--burn-subs]"
    exit 1
fi

# Configuration
MovieName="Example_Movie"
WorkDir="./work/$MovieName"
NASBase="/mnt/nas/media"
Preset="Your_Custom_Preset_Name"
QueueFile="./pipeline_queue.log"

mkdir -p "$WorkDir"

echo -e "\033[36mRegistering '$MovieName' in the encoding queue...\033[0m"
echo "$MovieName" >> "$QueueFile"

while true; do
    mapfile -t QueueLines < <(grep -v '^[[:space:]]*$' "$QueueFile" 2>/dev/null || true)
    
    if [ ${#QueueLines[@]} -gt 0 ] && [ "${QueueLines[0]}" = "$MovieName" ]; then
        echo -e "\033[32mStarting processing for '$MovieName'...\033[0m"
        break
    else
        echo -e "\033[33mAnother job is currently ahead in the queue. Waiting...\033[0m"
        sleep 30
    fi
done

# Step 1: MakeMKV Extraction (with optional bash progress tracking)
echo "[1/2] Checking work directory for existing MKV files..."

# Check if a raw MKV already exists (e.g., manual rip for playlist obfuscation)
RawMkvFile=$(find "$WorkDir" -maxdepth 1 -name "*.mkv" | head -n 1)

if [ -n "$RawMkvFile" ]; then
    echo "[1/2] Existing MKV file found. Skipping MakeMKV extraction."
else
    echo "[1/2] Starting MakeMKV extraction..."
    makemkvcon mkv disc:0 all "$WorkDir" --minlength=3600
    
    # Dynamically find the newly ripped file
    RawMkvFile=$(find "$WorkDir" -maxdepth 1 -name "*.mkv" | head -n 1)
    
    if [ -z "$RawMkvFile" ]; then
        echo "CRITICAL ERROR: MakeMKV failed to produce an MKV file."
        exit 1
    fi
fi

CompressedMkv="$WorkDir/${MovieName}.mkv"

# Step 2: Handle HandBrake Queueing & Compression
echo -e "\033[33m[2/2] Checking HandBrake queue status...\033[0m"

while pgrep -x "HandBrakeCLI" > /dev/null; do
    Timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    Msg="[$Timestamp] HandBrake is currently busy processing another title. '$MovieName' added to queue-wait state..."
    echo -e "\033[33m$Msg\033[0m"
    echo "$Msg" >> "$LogFile"
    sleep 30
done

# Dynamically grab the actual ripped MKV file from the work directory
RawMkvFile=$(find "$WorkDir" -maxdepth 1 -name "*.mkv" | head -n 1)

if [ -z "$RawMkvFile" ]; then
    echo -e "\033[31mCRITICAL ERROR: No raw MKV file found in $WorkDir to compress!\033[0m"
    exit 1
fi

echo -e "\033[32mHandBrake is free. Starting compression...\033[0m"

hbArgs=(
    "--preset-import-gui"
    "--input" "$RawMkvFile"
    "--output" "$CompressedMkv"
    "--preset" "$Preset"
    "--optimize"
)

# Append subtitle flags dynamically if requested via --burn-subs
if [ "$BurnSubs" = true ]; then
    echo -e "\033[33mSubtitle burn-in requested. Adding subtitle flags...\033[0m"
    hbArgs+=("--subtitle" "1" "--subtitle-burned" "1")
fi

HandBrakeCLI "${hbArgs[@]}"

if [ $HbExitCode -ne 0 ]; then
    echo ""
    echo "CRITICAL ERROR: HandBrake failed (Exit Code: $HbExitCode)."
    echo "Preset '$Preset' may be invalid or missing."
    echo "Your raw MKV is safely preserved in: $WorkDir"
    echo "Fix the issue and re-run. No re-rip necessary."
    exit 1
fi

echo -e "\033[32m\n[2/2] Compression complete.\033[0m"

# Step 3: Size Evaluation & NAS Transfer
FileSizeGB=$(du -b "$CompressedMkv" | awk '{print $1 / 1024 / 1024 / 1024}')
RoundedSize=$(printf "%.2f" "$FileSizeGB")
echo -e "\033[36mCompressed file size: $RoundedSize GB\033[0m"

Proceed=true
IsOverLimit=$(awk 'BEGIN {print ("$FileSizeGB" > 4.0) ? 1 : 0}')

if [ "$IsOverLimit" -eq 1 ]; then
    echo -e "\033[33mWarning: File size exceeds 4 GB threshold.\033[0m"
    read -p "Proceed with NAS move? (Y/N): " Response
    if [[ "$Response" != "Y" && "$Response" != "y" ]]; then
        Proceed=false
        echo -e "\033[31mNAS move aborted by user. File remains in local Videos.\033[0m"
    fi
fi

if [ "$Proceed" = true ]; then
    TargetDir="$NASBase/$MovieName"
    mkdir -p "$TargetDir"
    
    echo -e "\033[33mMoving file to NAS...\033[0m"
    mv "$CompressedMkv" "$TargetDir/$MovieName.mkv"

    # Remove the specific movie's temporary work directory
    if [ -d "$WorkDir" ]; then
        echo -e "\033[90mCleaning up temporary work directory...\033[0m"
        rm -rf "$WorkDir"
    fi

    if [ -f "$QueueFile" ]; then
        temp_file=$(mktemp)
        grep -v "^$MovieName$" "$QueueFile" > "$temp_file" || true
        
        if [ -s "$temp_file" ]; then
            mv "$temp_file" "$QueueFile"
            echo -e "\033[33mRemoved '$MovieName' from queue. Handing off to next job...\033[0m"
        else
            rm -f "$temp_file" "$QueueFile"
            echo -e "\033[90mQueue is now empty. Cleaned up queue file.\033[0m"
        fi
    fi

    echo -e "\033[32mPipeline finished successfully! Directory state restored.\033[0m"
fi