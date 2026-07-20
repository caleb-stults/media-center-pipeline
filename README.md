# Media Center Pipeline
Some scripts I created to automate my pipeline from MakeMKV ripping to Handbrake compressing to moving onto my NAS to stream on my Emby server. I put in some checks to ensure file size is small enough since these get streamed over a VPN server occassionally. 

## Prerequisites

Before running the scripts, ensure the following software tools are installed and accessible via your system's `PATH`:
* **MakeMKV** (specifically `makemkvcon`)
* **HandBrake** (specifically `HandBrakeCLI`)

## Available Scripts

### 1. PowerShell Script (`windows-pipeline.ps1`)
Designed for **Windows 10** environments. 

#### Features:
* **Smart Size Evaluation:** 
  * If the compressed file is **under 4 GB**, it automatically moves the file to the NAS and cleans up local raw files.
  * If the file is **over 4 GB**, it prompts for manual confirmation before proceeding with the move and cleanup.
* **NAS Integration:** Checks if the movie directory already exists on your network share. If it does, it updates the existing MKV file; if not, it creates the directory and moves the file into place.

#### Usage:
```powershell
& ".\windows-pipeline.ps1" -MovieName "Example Movie (2026)" -Preset "Your Preset Here"
```

### 2. Bash Script Template (linux-pipeline.sh)
Designed for Linux environments.

#### Features:
* **Smart Size Evaluation:** 
  * If the compressed file is **under 4 GB**, it automatically moves the file to the NAS and cleans up local raw files.
  * If the file is **over 4 GB**, it prompts for manual confirmation before proceeding with the move and cleanup.
* **NAS Integration:** Checks if the movie directory already exists on your network share. If it does, it updates the existing MKV file; if not, it creates the directory and moves the file into place.

#### Usage:
```bash
./linux-pipeline.sh "Example Movie (2026)" "Your Preset Here"
```

### Configuration
Make sure to adjust the configuration variables at the top of the scripts to match your local setup:
* `$DiscDrive` / `DISC_DRIVE`: Optical drive index (default is `"dev:0"`). Run `makemkvcon -r info disc:9999` to verify your drive identifier if needed.
* `$NASBase` / `NAS_BASE`: The destination path for your movie library.