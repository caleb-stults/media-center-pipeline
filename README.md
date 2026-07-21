# Media Center Pipeline
Some scripts I created to automate my pipeline from MakeMKV ripping to Handbrake compressing to moving onto my NAS to stream on my Emby server. I put in some checks to ensure file size is small enough since these get streamed over a VPN server occassionally. This script is intended for grabbing just the movie file, none of the special features. For fringe cases of multiple cuts, special features, or playlist obfuscation, the script will stop so the process can be done manually.

## Prerequisites

Before running the scripts, ensure the following software tools are installed and accessible via your system's `PATH`:
* **MakeMKV** (specifically `makemkvcon`)
* **HandBrake** (specifically `HandBrakeCLI`)

## Available Scripts

### 1. PowerShell Script (`windows-pipeline.ps1`)
Designed for **Windows 10** environments. 

#### Features:
* **Queue Management:** 
  * Features a robust text-file queue (`pipeline_queue.log`) that registers new jobs atomically and processes them strictly in the order they were submitted, preventing race conditions or jobs jumping the line.
  * Script will stop if it detects more than one file meeting the criteria to prevent you from grabbing multiple cuts of a movie or protect you from getting dozens of worthless files in the case of playlist obfuscation.
* **Smart Size Evaluation:** 
  * If the compressed file is **under 4 GB**, it automatically moves the file to the NAS and cleans up local raw files.
  * If the file is **over 4 GB**, it prompts for manual confirmation before proceeding with the move and cleanup.
* **NAS Integration:** Checks if the movie directory already exists on your network share. If it does, it updates the existing MKV file; if not, it creates the directory and moves the file into place.
* **Automatic Cleanup & State Restoration:** Added precise teardown steps that remove temporary work directories upon completion and automatically clean up the `pipeline_queue.log` file once the final job in the queue finishes.

#### Usage:
```powershell
& ".\windows-pipeline.ps1" -MovieName "Example Movie (2026)" -Preset "Your Preset Here" -BurnSubs
# Add -BurnSubs if you want to burn in the subtitles
```

### 2. Bash Script Template (linux-pipeline.sh)
Designed for Linux environments.

#### Features:
* **Live Progress Monitoring:** 
  * Displays progress of MakeMKV ripping and Handbrake compression. Also queues Handbrake jobs if current job is running.
  * Utilizes a text-file queue (`pipeline_queue.log`) to ensure jobs wait their turn sequentially and hand off cleanly when finished.
  * Script will stop if it detects more than one file meeting the criteria to prevent you from grabbing multiple cuts of a movie or protect you from getting dozens of worthless files in the case of playlist obfuscation.
* **Smart Size Evaluation:** 
  * If the compressed file is **under 4 GB**, it automatically moves the file to the NAS and cleans up local raw files.
  * If the file is **over 4 GB**, it prompts for manual confirmation before proceeding with the move and cleanup.
* **NAS Integration:** Checks if the movie directory already exists on your network share. If it does, it updates the existing MKV file; if not, it creates the directory and moves the file into place.
* **Automatic Cleanup & State Restoration:** Added precise teardown steps that remove temporary work directories upon completion and automatically clean up the `pipeline_queue.log` file once the final job in the queue finishes.

#### Usage:
```bash
./linux-pipeline.sh "Example Movie (2026)" "Your Preset Here" --burn-subs
# Add --burn-subs if you want the subtitles burned in
```

### Configuration
Make sure to adjust the configuration variables at the top of the scripts to match your local setup:
* `$DiscDrive` / `DISC_DRIVE`: Optical drive index (default is `"disc:0"`). Run `makemkvcon64 -r info disc:9999` to verify your drive identifier if needed.
* `$NASBase` / `NAS_BASE`: The destination path for your movie library.