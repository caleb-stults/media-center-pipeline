param (
    [Parameter(Mandatory=$true)][string]$MovieName,
    [Parameter(Mandatory=$true)][ValidateSet("4k Subtitle", "Blu-Ray")][string]$Preset
)

# Configuration
$DiscDrive = "dev:0"
$NASBase = "Z:\Movies"
$WorkDir = "$env:USERPROFILE\Videos"
$RawFolder = Join-Path $WorkDir $MovieName
$RawMkv = Join-Path $RawFolder "$MovieName.mkv"
$CompressedFile = Join-Path $WorkDir "$MovieName.mkv"
$SizeLimit = 4GB

# 1. MakeMKV
if (!(Test-Path $RawFolder)) { New-Item -ItemType Directory -Path $RawFolder | Out-Null }
makemkvcon mkv $DiscDrive all "$RawFolder" --minlength=3600 --noscan

# 2. HandBrake
HandBrakeCLI -i "$RawMkv" -o "$CompressedFile" --preset "$Preset"

# 3. File Size Logic
$File = Get-Item $CompressedFile
$Proceed = $false

if ($File.Length -lt $SizeLimit) {
    Write-Host "File size is $($File.Length / 1MB) MB. Auto-processing..."
    $Proceed = $true
} else {
    Write-Host "File size is $($File.Length / 1GB) GB (Over 4 GB)."
    $confirm = Read-Host "Proceed with move and cleanup? (Y/N)"
    if ($confirm -eq 'Y') { $Proceed = $true }
}

# 4. Move and Cleanup
if ($Proceed) {
    $TargetDir = Join-Path $NASBase $MovieName
    if (!(Test-Path $TargetDir)) { New-Item -ItemType Directory -Path $TargetDir | Out-Null }
    
    Move-Item -Path $CompressedFile -Destination (Join-Path $TargetDir "$MovieName.mkv") -Force
    Remove-Item -Path $RawFolder -Recurse -Force
    Write-Host "Process complete."
} else {
    Write-Host "Process aborted by user."
}