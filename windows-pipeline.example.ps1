param(
    [Parameter(Mandatory=$true)]
    [string]$MovieName,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet("Preset 1", "Preset 2", "Preset 3")]
    [string]$Preset,

    [Parameter(Mandatory=$false)]
    [switch]$BurnSubs
)

# Configuration
$DiscDrive = "disc:0"
$NASBase = "path\to\nas\movies"
$LocalVideos = "$env:USERPROFILE\Videos"
$WorkDir = Join-Path $LocalVideos $MovieName
$RawMkv = Join-Path $WorkDir "$MovieName.mkv"
$CompressedMkv = Join-Path $LocalVideos "$MovieName.mkv"
$LogFile = Join-Path $LocalVideos "pipeline_queue.log"
$QueueFile = Join-Path $LocalVideos "pipeline_queue.txt"

Write-Host "Starting Rip Pipeline for: $MovieName" -ForegroundColor Cyan

# Step 1: MakeMKV Extraction
if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir | Out-Null
}

$existingMkv = @(Get-ChildItem -Path $WorkDir -Filter "*.mkv")

if ($existingMkv.Count -gt 0) {
    Write-Host "[1/2] MKV files already exist in $WorkDir. Skipping MakeMKV extraction." -ForegroundColor DarkYellow
} else {
    Write-Host "[1/2] Ripping disc with MakeMKV..." -ForegroundColor Yellow
    Write-Host "(MakeMKV will say 'Saving title' and wait here until the rip is finished)" -ForegroundColor Gray
    
    & makemkvcon64 --minlength=3600 mkv $DiscDrive all "$WorkDir"

    Write-Host "`n[1/2] MakeMKV extraction complete." -ForegroundColor Green

    $extractedFiles = @(Get-ChildItem -Path $WorkDir -Filter "*.mkv")

    if ($extractedFiles.Count -eq 0) {
        Write-Host "Error: No titles met the minimum length requirement (3600s)." -ForegroundColor Red
        exit 1
    }
    elseif ($extractedFiles.Count -gt 1) {
        Write-Host "WARNING: Detected $($extractedFiles.Count) files instead of 1!" -ForegroundColor Red
        Write-Host "This disc uses playlist obfuscation or contains multiple cuts." -ForegroundColor Yellow
        Write-Host "Wiping partial files and halting pipeline. Check source manually." -ForegroundColor Yellow
        Remove-Item -Path $WorkDir -Recurse -Force
        exit 1
    }
}

# Step 2: Handle HandBrake Queueing & Compression
Write-Host "[2/2] Checking HandBrake queue status..." -ForegroundColor Yellow

Write-Host "Registering '$MovieName' in the encoding queue..." -ForegroundColor Cyan
[System.IO.File]::AppendAllText($QueueFile, "$MovieName`n")

while ($true) {
    $QueueLines = @(Get-Content -Path $QueueFile -ErrorAction SilentlyContinue | Where-Object { $_.Trim().Length -gt 0 })
    
    if ($QueueLines -and $QueueLines[0].Trim() -eq $MovieName) {
        Write-Host "Starting processing for '$MovieName'..." -ForegroundColor Green
        break
    } else {
        Write-Host "Another job is currently ahead in the queue. Waiting..." -ForegroundColor Yellow
        Start-Sleep -Seconds 30
    }
}

function Test-HandBrakeRunning {
    $hbProcesses = Get-Process -Name "HandBrakeCLI" -ErrorAction SilentlyContinue
    return ($null -ne $hbProcesses)
}

while (Test-HandBrakeRunning) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $msg = "[$timestamp] HandBrake is currently busy processing another title. '$MovieName' added to queue-wait state..."
    Write-Host $msg -ForegroundColor DarkYellow
    Add-Content -Path $LogFile -Value $msg
    Start-Sleep -Seconds 30
}

# Dynamically grab the actual ripped MKV file from the work directory so filename mismatches never happen
$RawMkvFile = Get-ChildItem -Path $WorkDir -Filter "*.mkv" | Select-Object -ExpandProperty FullName

if (-not $RawMkvFile) {
    Write-Host "CRITICAL ERROR: No raw MKV file found in $WorkDir to compress!" -ForegroundColor Red
    exit 1
}

Write-Host "HandBrake is free. Starting compression..." -ForegroundColor Green
$hbArgs = @(
    "--preset-import-gui",
    "--input", "$RawMkvFile",
    "--output", "$CompressedMkv",
    "--preset", "$Preset",
    "--optimize"
)

if ($BurnSubs) {
    Write-Host "Subtitle burn-in requested. Adding subtitle flags..." -ForegroundColor Yellow
    # Note: track 1 is typically English/Primary, and --subtitle-burned forces it directly into the video stream
    $hbArgs += @("--subtitle", "1", "--subtitle-burned", "1")
}

# Run HandBrake and capture output while retaining exit code tracking
& HandBrakeCLI $hbArgs 2>&1 | ForEach-Object {
    if ($_ -match "Encoding: task") {
        Write-Host -NoNewline "`r$_   "
    } else {
        $_
    }
}

# Explicitly check if HandBrake actually succeeded
if ($LASTEXITCODE -ne 0) {
    Write-Host "CRITICAL ERROR: HandBrake failed (Exit Code: $LASTEXITCODE)." -ForegroundColor Red
    Write-Host "Preset '$Preset' may be invalid or missing." -ForegroundColor Yellow
    Write-Host "Your raw MKV is safely preserved in: $WorkDir" -ForegroundColor Yellow
    Write-Host "Fix the issue and re-run. No re-rip necessary." -ForegroundColor Yellow
    exit 1
}

Write-Host "`n[2/2] Compression complete." -ForegroundColor Green

# Step 3: Size Evaluation & NAS Transfer
$fileSizeGB = (Get-Item $CompressedMkv).Length / 1GB
Write-Host "Compressed file size: $([math]::Round($fileSizeGB, 2)) GB" -ForegroundColor Cyan

$proceed = $true
if ($fileSizeGB -gt 4.0) {
    Write-Host "Warning: File size exceeds 4 GB threshold." -ForegroundColor Yellow
    $response = Read-Host "Proceed with NAS move? (Y/N)"
    if ($response -ne 'Y') {
        $proceed = $false
        Write-Host "NAS move aborted by user. File remains in local Videos." -ForegroundColor Red
    }
}

if ($proceed) {
    $TargetDir = Join-Path $NASBase $MovieName
    if (-not (Test-Path $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir | Out-Null
    }
    
    Write-Host "Moving file to NAS..." -ForegroundColor Yellow
    Move-Item -Path $CompressedMkv -Destination "$TargetDir\$MovieName.mkv" -Force

    # Remove the specific movie's temporary work directory
    if (Test-Path -Path $WorkDir) {
        Write-Host "Cleaning up temporary work directory..." -ForegroundColor Gray
        Remove-Item -Path $WorkDir -Recurse -Force
    }

    if (Test-Path -Path $QueueFile) {
        $QueueLines = Get-Content -Path $QueueFile -ErrorAction SilentlyContinue | Where-Object { $_.Trim().Length -gt 0 }
        $RemainingQueue = $QueueLines | Where-Object { $_.Trim() -ne $MovieName }
        
        if ($RemainingQueue) {
            Set-Content -Path $QueueFile -Value $RemainingQueue
            Write-Host "Removed '$MovieName' from queue. Handing off to next job..." -ForegroundColor DarkYellow
        } else {
            Remove-Item -Path $QueueFile -Force
            Write-Host "Queue is now empty. Cleaned up queue file." -ForegroundColor Gray
        }
    }

    Write-Host "Pipeline finished successfully! Directory state restored." -ForegroundColor Green
}