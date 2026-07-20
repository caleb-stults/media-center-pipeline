param(
    [Parameter(Mandatory=$true)]
    [string]$MovieName,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet("Preset 1", "Preset 2", "Preset 3")]
    [string]$Preset
)

# --- Configuration ---
$DiscDrive = "dev:0"
$NASBase = "\path\to\NAS\"
$LocalVideos = "$env:USERPROFILE\Videos"
$WorkDir = Join-Path $LocalVideos $MovieName
$RawMkv = Join-Path $WorkDir "$MovieName.mkv"
$CompressedMkv = Join-Path $LocalVideos "$MovieName.mkv"
$LogFile = Join-Path $LocalVideos "pipeline_queue.log"

Write-Host "=== Starting Rip Pipeline for: $MovieName ===" -ForegroundColor Cyan

# Step 1: MakeMKV Extraction with Live Progress
if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir | Out-Null
}

Write-Host "[1/2] Ripping disc with MakeMKV..." -ForegroundColor Yellow
$makemkvArgs = @("-r", "mkv", $DiscDrive, "all", "$WorkDir", "--minlength=3600")

$makemkvProcess = Start-Process -FilePath "makemkvcon" -ArgumentList $makemkvArgs -NoNewWindow -PassThru -RedirectStandardOutput "$WorkDir\makemkv_out.log"

& makemkvcon $makemkvArgs | ForEach-Object {
    if ($_ -match "PRGV:") {
        $parts = $_ -split ","
        if ($parts.Count -ge 3) {
            Write-Host -NoNewline "`r[MakeMKV Progress] Task: $($parts[1]) - Current: $($parts[2] / 10)%   "
        }
    } else {
        $_
    }
}
$makemkvProcess.WaitForExit()
Write-Host "`n[1/2] MakeMKV extraction complete." -ForegroundColor Green

# Step 2: Handle HandBrake Queueing
Write-Host "[2/2] Checking HandBrake queue status..." -ForegroundColor Yellow

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

Write-Host "HandBrake is free. Starting compression..." -ForegroundColor Green
$hbArgs = @(
    "--input", "$RawMkv",
    "--output", "$CompressedMkv",
    "--preset", "$Preset",
    "--optimize"
)

& HandBrakeCLI $hbArgs 2>&1 | ForEach-Object {
    if ($_ -match "Encoding: task") {
        Write-Host -NoNewline "`r$_   "
    } else {
        $_
    }
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
    Remove-Item -Path $WorkDir -Recurse -Force
    Write-Host "Pipeline finished successfully!" -ForegroundColor Green
}