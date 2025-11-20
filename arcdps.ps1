#!/usr/bin/env pwsh
# PowerShell 7 script to manage arcdps d3d11.dll for Guild Wars 2
# Usage: ./arcdps.ps1 [Disable|Enable|Update]
#   (no parameters) - Updates arcdps to the latest version (default)
#   Disable - Renames d3d11.dll to d3d11.dll.arcdps
#   Enable  - Renames d3d11.dll.arcdps back to d3d11.dll, or downloads if disabled file doesn't exist
#   Update  - Updates arcdps to the latest version

param(
    [Parameter(Position=0)]
    [ValidateSet("Disable", "Enable", "Update")]
    [string]$Action = "Update"
)

$ErrorActionPreference = "Stop"

# Configuration
$BaseUrl = "https://www.deltaconnected.com/arcdps/x64/"
$DllFileName = "d3d11.dll"
$Md5FileName = "d3d11.dll.md5sum"

# Function to find Guild Wars 2 installation path
function Find-Gw2Path {
    $HomePath = (Resolve-Path ~).Path
    $PossiblePaths = @(
        Join-Path $HomePath ".local/share/Steam/steamapps/common/Guild Wars 2"
        Join-Path $HomePath ".steam/steam/steamapps/common/Guild Wars 2"
        Join-Path $HomePath ".steam/steam/steamapps/common/steamapps/common/Guild Wars 2"
    )
    
    foreach ($path in $PossiblePaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    return $null
}

# Guild Wars 2 installation path
$Gw2Path = Find-Gw2Path
if (-not $Gw2Path) {
    # Default to most common location if not found
    $HomePath = (Resolve-Path ~).Path
    $Gw2Path = Join-Path $HomePath ".local/share/Steam/steamapps/common/Guild Wars 2"
}

$DllPath = Join-Path $Gw2Path $DllFileName
$DisabledPath = Join-Path $Gw2Path "$DllFileName.arcdps"
$BackupPath = Join-Path $Gw2Path "$DllFileName.backup"


# Function to download file
function Get-RemoteFile {
    param(
        [string]$Url,
        [string]$OutputPath
    )
    
    Write-Host "Downloading from $Url..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing
    Write-Host "Downloaded to $OutputPath" -ForegroundColor Green
}

# Function to calculate MD5 hash
function Get-FileMD5 {
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        return $null
    }
    
    $hash = Get-FileHash -Path $FilePath -Algorithm MD5
    return $hash.Hash.ToLower()
}

# Function to disable arcdps
function Disable-Arcdps {
    Write-Host "=== Disabling arcdps ===" -ForegroundColor Yellow
    Write-Host ""
    
    # Check if GW2 path exists
    if (-not (Test-Path $Gw2Path)) {
        Write-Error "Guild Wars 2 path not found: $Gw2Path"
        Write-Host "Please verify your Steam installation path." -ForegroundColor Red
        exit 1
    }
    
    if (-not (Test-Path $DllPath)) {
        Write-Host "d3d11.dll not found. Nothing to disable." -ForegroundColor Yellow
        exit 0
    }
    
    if (Test-Path $DisabledPath) {
        Write-Host "d3d11.dll.arcdps already exists. Removing it first..." -ForegroundColor Yellow
        Remove-Item $DisabledPath -Force
    }
    
    Write-Host "Renaming d3d11.dll to d3d11.dll.arcdps..." -ForegroundColor Cyan
    Rename-Item -Path $DllPath -NewName "$DllFileName.arcdps" -Force
    Write-Host "arcdps has been disabled!" -ForegroundColor Green
}

# Function to enable arcdps
function Enable-Arcdps {
    Write-Host "=== Enabling arcdps ===" -ForegroundColor Yellow
    Write-Host ""
    
    # Check if GW2 path exists
    if (-not (Test-Path $Gw2Path)) {
        Write-Error "Guild Wars 2 path not found: $Gw2Path"
        Write-Host "Please verify your Steam installation path." -ForegroundColor Red
        exit 1
    }
    
    # If disabled file exists, rename it back
    if (Test-Path $DisabledPath) {
        if (Test-Path $DllPath) {
            Write-Host "d3d11.dll already exists. Removing it first..." -ForegroundColor Yellow
            Remove-Item $DllPath -Force
        }
        
        Write-Host "Renaming d3d11.dll.arcdps back to d3d11.dll..." -ForegroundColor Cyan
        Rename-Item -Path $DisabledPath -NewName $DllFileName -Force
        Write-Host "arcdps has been enabled!" -ForegroundColor Green
    }
    else {
        Write-Host "No disabled file found. Downloading and installing arcdps..." -ForegroundColor Cyan
        Write-Host ""
        Update-Arcdps
    }
}

# Function to update arcdps
function Update-Arcdps {
    Write-Host "=== arcdps Update Script ===" -ForegroundColor Yellow
    Write-Host ""
    
    # Check if GW2 path exists
    if (-not (Test-Path $Gw2Path)) {
        Write-Error "Guild Wars 2 path not found: $Gw2Path"
        Write-Host "Please verify your Steam installation path." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "GW2 Path: $Gw2Path" -ForegroundColor Cyan
    Write-Host ""
    
    # Determine temp directory (cross-platform)
    $TempDir = [System.IO.Path]::GetTempPath()
    
    # Download MD5 file to check version
    $TempMd5Path = Join-Path $TempDir "d3d11.dll.md5sum"
    try {
        Get-RemoteFile -Url "$BaseUrl$Md5FileName" -OutputPath $TempMd5Path
        $Md5Content = (Get-Content $TempMd5Path -Raw).Trim()
        # Extract just the hash (first 32 characters or first word before whitespace)
        $RemoteMd5 = ($Md5Content -split '\s+')[0].ToLower()
        Write-Host "Remote MD5: $RemoteMd5" -ForegroundColor Cyan
    }
    catch {
        Write-Error "Failed to download MD5 file: $_"
        exit 1
    }
    
    # Get current installed DLL's MD5 hash (if it exists)
    $CurrentMd5 = if (Test-Path $DllPath) {
        Get-FileMD5 -FilePath $DllPath
    } else {
        $null
    }
    Write-Host "Current MD5: $(if ($CurrentMd5) { $CurrentMd5 } else { 'None (dll not installed)' })" -ForegroundColor Cyan
    Write-Host ""
    
    # Check if update is needed
    if ($RemoteMd5 -eq $CurrentMd5) {
        Write-Host "d3d11.dll is already up to date!" -ForegroundColor Green
        Remove-Item $TempMd5Path -ErrorAction SilentlyContinue
        exit 0
    }
    
    Write-Host "New version detected! Updating..." -ForegroundColor Yellow
    Write-Host ""
    
    # Backup existing dll if it exists
    if (Test-Path $DllPath) {
        $ExistingMd5 = Get-FileMD5 -FilePath $DllPath
        
        # Only backup if it's different from what we're about to install
        if ($ExistingMd5 -ne $RemoteMd5) {
            Write-Host "Backing up existing d3d11.dll..." -ForegroundColor Cyan
            
            # Remove old backup if it exists (we only keep the previous version)
            if (Test-Path $BackupPath) {
                Remove-Item $BackupPath -Force
                Write-Host "Removed old backup" -ForegroundColor Gray
            }
            
            Copy-Item -Path $DllPath -Destination $BackupPath -Force
            Write-Host "Backup created: $BackupPath" -ForegroundColor Green
        }
        else {
            Write-Host "Existing file matches remote version, skipping backup" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "No existing d3d11.dll found, skipping backup" -ForegroundColor Gray
    }
    
    # Download new dll
    $TempDllPath = Join-Path $TempDir $DllFileName
    try {
        Get-RemoteFile -Url "$BaseUrl$DllFileName" -OutputPath $TempDllPath
        
        # Verify downloaded file matches MD5
        $DownloadedMd5 = Get-FileMD5 -FilePath $TempDllPath
        if ($DownloadedMd5 -ne $RemoteMd5) {
            Write-Error "MD5 mismatch! Expected: $RemoteMd5, Got: $DownloadedMd5"
            Remove-Item $TempDllPath -ErrorAction SilentlyContinue
            exit 1
        }
        
        Write-Host "MD5 verification passed" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to download d3d11.dll: $_"
        exit 1
    }
    
    # Copy to GW2 folder
    Write-Host ""
    Write-Host "Installing d3d11.dll to GW2 folder..." -ForegroundColor Cyan
    try {
        Copy-Item -Path $TempDllPath -Destination $DllPath -Force
        Write-Host "Successfully installed d3d11.dll!" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to copy d3d11.dll: $_"
        Remove-Item $TempDllPath -ErrorAction SilentlyContinue
        exit 1
    }
    
    # Cleanup temp files
    Remove-Item $TempDllPath -ErrorAction SilentlyContinue
    Remove-Item $TempMd5Path -ErrorAction SilentlyContinue
    
    Write-Host ""
    Write-Host "=== Update Complete ===" -ForegroundColor Green
    Write-Host "New version installed: $RemoteMd5" -ForegroundColor Green
}

# Main script logic
switch ($Action) {
    "Disable" {
        Disable-Arcdps
    }
    "Enable" {
        Enable-Arcdps
    }
    "Update" {
        Update-Arcdps
    }
}
