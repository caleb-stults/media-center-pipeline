# Media Center Pipeline
I made these scripts to automate my pipeline from ripping to compressing to moving onto my NAS for playback on my Emby server. I made Windows and Linux versions of the script to account for whatever machine I'm using. You definitely don't need to use these but it's a way for me to streamline my process. My goal is to get small files for easy streaming over a VPN, which is why you'll see the check for the compressed file size.

## Prerequisites

Before running the scripts, ensure the following software tools are installed and accessible via your system's `PATH`:
* **MakeMKV** (specifically `makemkvcon`)
* **HandBrake** (specifically `HandBrakeCLI`)

## Available Scripts

### 1. PowerShell Script (`windows-pipeline.ps1`)
Designed for **Windows 10** environments. 

#### Features:
* **Automated Extraction:** Creates a temporary working folder named after the movie in your local `Videos` directory and rips the main feature title using MakeMKV.
* **Compression:** Compresses the raw MKV using a specified HandBrake preset
* **Smart Size Evaluation:** 
  * If the compressed file is **under 4 GB**, it automatically moves the file to the NAS and cleans up local raw files.
  * If the file is **over 4 GB**, it prompts for manual confirmation before proceeding with the move and cleanup.
* **NAS Integration:** Checks if the movie directory already exists on your network share. If it does, it updates the existing MKV file; if not, it creates the directory and moves the file into place.

#### Usage:
```powershell
& ".\windows-pipeline.ps1" -MovieName "Example Movie (2026)" -Preset "Preset Name Here"
```

### 2. Bash Script Template (linux-pipeline.sh)
Designed for Linux environments.

#### Features:
* All in One: Gives you one script to run to go from your disc to your compressed file on your NAS ready to stream.
* Conditional Size Guard: Evaluates compressed file size against a 4 GB threshold, offering automated handling for smaller files and manual confirmation for larger ones.

#### Usage:
```bash
./linux-pipeline.sh "Example Movie (2026)" "4k Subtitle"
```

### Configuration
Make sure to adjust the configuration variables at the top of the scripts to match your local setup:
* `$DiscDrive` / `DISC_DRIVE`: Optical drive index (default is `"dev:0"`). Run `makemkvcon -r info disc:9999` to verify your drive identifier if needed.
* `$NASBase` / `NAS_BASE`: The destination path for your movie library.