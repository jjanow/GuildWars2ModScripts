#!/usr/bin/env pwsh
# PowerShell 7 script to manage Burrito d3d11.dll for Guild Wars 2
# Usage: ./burrito.ps1 [Disable|Enable|Update] [-Channel stable|next] [-InstallPath <path>]
#   (no parameters) - Updates Burrito to the latest version (default)
#   Disable - Renames installed dll (d3d11.dll or d3d11_chainload.dll) to .burrito
#   Enable  - Renames .burrito file back to dll
#   Update  - Updates Burrito to the latest version
#   Troubleshoot - Runs diagnostic checks for common Linux issues
#   -Channel - Select release channel: "stable" (default) or "next" (preview)
#   -InstallPath - Directory to install the Burrito overlay app (default: ~/burrito)

param(
    [Parameter(Position=0)]
    [ValidateSet("Disable", "Enable", "Update", "Troubleshoot")]
    [string]$Action = "Update",
    
    [Parameter()]
    [ValidateSet("stable", "next")]
    [string]$Channel = "stable",

    [Parameter()]
    [string]$InstallPath = "~/burrito"
)

$ErrorActionPreference = "Stop"

# Configuration
$GitHubRepo = "AsherGlick/Burrito"
$GitHubApiBase = "https://api.github.com/repos/$GitHubRepo"
$DllFileName = "d3d11.dll"
$ChainloadFileName = "arcdps_burrito.dll"
$ExtraFiles = @("burrito_link.exe")
$ArcdpsBaseUrl = "https://www.deltaconnected.com/arcdps/x64/"
$ArcdpsMd5FileName = "d3d11.dll.md5sum"

# Resolve Install Path
$ResolvedInstallPath = $InstallPath.Replace("~", $HOME)

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
$ChainloadPath = Join-Path $Gw2Path $ChainloadFileName
$DisabledPath = Join-Path $Gw2Path "$DllFileName.burrito"
$DisabledChainloadPath = Join-Path $Gw2Path "$ChainloadFileName.burrito"

# Function to download file
function Get-RemoteFile {
    param(
        [string]$Url,
        [string]$OutputPath
    )
    
    Write-Host "Downloading from $Url..." -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -UserAgent "PowerShell-Burrito-Manager"
    }
    catch {
        Write-Error "Failed to download file: $_"
        throw
    }
    Write-Host "Downloaded to $OutputPath" -ForegroundColor Green
}

# Function to calculate SHA256 hash
function Get-FileSHA256 {
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        return $null
    }
    
    $hash = Get-FileHash -Path $FilePath -Algorithm SHA256
    return $hash.Hash.ToLower()
}

# Function to calculate MD5 hash (for Arcdps detection)
function Get-FileMD5 {
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        return $null
    }
    
    $hash = Get-FileHash -Path $FilePath -Algorithm MD5
    return $hash.Hash.ToLower()
}

# Function to detect if d3d11.dll is Arcdps
function Test-Arcdps {
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        return $false
    }
    
    Write-Host "Checking if $FilePath is Arcdps..." -ForegroundColor Cyan
    
    # Get remote MD5
    $TempDir = [System.IO.Path]::GetTempPath()
    $TempMd5Path = Join-Path $TempDir "arcdps_check.md5"
    
    try {
        Get-RemoteFile -Url "$ArcdpsBaseUrl$ArcdpsMd5FileName" -OutputPath $TempMd5Path
        $Md5Content = (Get-Content $TempMd5Path -Raw).Trim()
        $RemoteMd5 = ($Md5Content -split '\s+')[0].ToLower()
        Remove-Item $TempMd5Path -ErrorAction SilentlyContinue
        
        $LocalMd5 = Get-FileMD5 -FilePath $FilePath
        
        if ($LocalMd5 -eq $RemoteMd5) {
            Write-Host "Identified Arcdps (MD5 match)" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Warning "Failed to check Arcdps MD5: $_"
    }
    
    return $false
}

# Function to get latest release from GitHub
function Get-LatestRelease {
    param([string]$ReleaseChannel)
    
    Write-Host "Fetching latest $ReleaseChannel release from GitHub..." -ForegroundColor Cyan
    
    try {
        $releasesUrl = "$GitHubApiBase/releases"
        $headers = @{
            "Accept" = "application/vnd.github.v3+json"
            "User-Agent" = "PowerShell-Burrito-Manager"
        }
        
        $response = Invoke-RestMethod -Uri $releasesUrl -Headers $headers -UseBasicParsing
    }
    catch {
        Write-Error "Failed to fetch releases from GitHub: $_"
        exit 1
    }
    
    # Filter releases based on channel
    if ($ReleaseChannel -eq "stable") {
        $releases = $response | Where-Object { 
            -not $_.prerelease -and $_.tag_name -notlike "*next*" 
        } | Sort-Object { [DateTime]$_.published_at } -Descending
    }
    else {
        $releases = $response | Where-Object { 
            $_.prerelease -or $_.tag_name -like "*next*" 
        } | Sort-Object { [DateTime]$_.published_at } -Descending
    }
    
    if (-not $releases -or $releases.Count -eq 0) {
        Write-Error "No $ReleaseChannel releases found"
        exit 1
    }
    
    $latestRelease = $releases[0]
    Write-Host "Latest $ReleaseChannel release: $($latestRelease.tag_name)" -ForegroundColor Green
    
    # Find d3d11.dll asset
    $dllAsset = $latestRelease.assets | Where-Object { $_.name -eq $DllFileName }
    
    if (-not $dllAsset) {
        $zipAsset = $latestRelease.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
        
        if (-not $zipAsset) {
            Write-Error "No d3d11.dll or zip file found in release $($latestRelease.tag_name)"
            exit 1
        }
        
        return @{
            TagName = $latestRelease.tag_name
            PublishedAt = $latestRelease.published_at
            Asset = $zipAsset
            IsZip = $true
        }
    }
    
    return @{
        TagName = $latestRelease.tag_name
        PublishedAt = $latestRelease.published_at
        Asset = $dllAsset
        IsZip = $false
    }
}

# Function to extract extra files (e.g. burrito_link.exe)
function Expand-ExtraFiles {
    param(
        [string]$ZipPath,
        [string]$DestinationPath
    )
    
    foreach ($file in $ExtraFiles) {
        try {
            Expand-ZipFile -ZipPath $ZipPath -DestinationPath $DestinationPath -TargetFile $file -ErrorAction SilentlyContinue
        }
        catch {
            Write-Warning "Could not find extra file $file in archive (might be optional or missing in this version)"
        }
    }
}

# Function to extract zip file
function Expand-ZipFile {
    param(
        [string]$ZipPath,
        [string]$DestinationPath,
        [string]$TargetFile,
        [System.Management.Automation.ActionPreference]$ErrorAction = "Stop"
    )
    
    Write-Host "Extracting $TargetFile from archive..." -ForegroundColor Cyan
    
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        
        $entry = $zip.Entries | Where-Object { 
            $_.Name -eq $TargetFile 
        } | Select-Object -First 1
        
        if (-not $entry) {
            $entry = $zip.Entries | Where-Object { 
                $_.FullName -like "*$TargetFile" -and -not $_.FullName.EndsWith("/")
            } | Select-Object -First 1
        }
        
        if (-not $entry) {
            $zip.Dispose()
            if ($ErrorAction -ne "SilentlyContinue") {
                Write-Error "Could not find $TargetFile in archive"
                throw
            }
            return $null
        }
        
        Write-Host "Found $TargetFile at: $($entry.FullName)" -ForegroundColor Cyan
        
        $extractPath = Join-Path $DestinationPath $TargetFile
        $entryDir = Split-Path -Parent $extractPath
        if ($entryDir -and $entryDir -ne $DestinationPath -and -not (Test-Path $entryDir)) {
            New-Item -ItemType Directory -Path $entryDir -Force | Out-Null
        }
        
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $extractPath, $true)
        $zip.Dispose()
        
        Write-Host "Extracted $TargetFile" -ForegroundColor Green
        return $extractPath
    }
    catch {
        if ($ErrorAction -ne "SilentlyContinue") {
            Write-Error "Failed to extract zip file: $_"
            throw
        }
        return $null
    }
}

# Function to disable Burrito
function Disable-Burrito {
    Write-Host "=== Disabling Burrito ===" -ForegroundColor Yellow
    Write-Host ""
    
    if (-not (Test-Path $Gw2Path)) {
        Write-Error "Guild Wars 2 path not found: $Gw2Path"
        exit 1
    }
    
    # Try to find what to disable
    if (Test-Path $ChainloadPath) {
        Write-Host "Found Burrito as $ChainloadFileName. Renaming to .burrito..." -ForegroundColor Cyan
        Rename-Item -Path $ChainloadPath -NewName "$ChainloadFileName.burrito" -Force
        Write-Host "Burrito disabled (was chainloaded)." -ForegroundColor Green
        return
    }
    
    if (Test-Path $DllPath) {
        # Check if this is likely Burrito (optional logic, but for disable we just rename if asked)
        # If Arcdps is installed as d3d11.dll, we might be disabling Arcdps if we are not careful.
        # But the user invoked burrito.ps1 Disable.
        
        if (Test-Arcdps $DllPath) {
            Write-Warning "d3d11.dll appears to be Arcdps. Not disabling it."
            Write-Warning "Burrito (chainload) was not found."
            return
        }
        
        Write-Host "Renaming d3d11.dll to d3d11.dll.burrito..." -ForegroundColor Cyan
        Rename-Item -Path $DllPath -NewName "$DllFileName.burrito" -Force
        Write-Host "Burrito has been disabled!" -ForegroundColor Green
        return
    }
    
    Write-Host "Burrito dll not found. Nothing to disable." -ForegroundColor Yellow
}

# Function to enable Burrito
function Enable-Burrito {
    Write-Host "=== Enabling Burrito ===" -ForegroundColor Yellow
    Write-Host ""
    
    if (-not (Test-Path $Gw2Path)) {
        Write-Error "Guild Wars 2 path not found: $Gw2Path"
        exit 1
    }
    
    # Check chainload disabled file
    if (Test-Path $DisabledChainloadPath) {
        if (Test-Path $ChainloadPath) {
            Remove-Item $ChainloadPath -Force
        }
        Rename-Item -Path $DisabledChainloadPath -NewName $ChainloadFileName -Force
        Write-Host "Burrito enabled as $ChainloadFileName." -ForegroundColor Green
        return
    }
    
    # Check regular disabled file
    if (Test-Path $DisabledPath) {
        # We need to check if d3d11.dll is occupied by Arcdps
        if (Test-Path $DllPath) {
            if (Test-Arcdps $DllPath) {
                Write-Host "d3d11.dll is Arcdps. Enabling Burrito as chainload..." -ForegroundColor Cyan
                Rename-Item -Path $DisabledPath -NewName $ChainloadFileName -Force
                Write-Host "Burrito enabled as $ChainloadFileName (chainloaded)." -ForegroundColor Green
                return
            }
            else {
                Write-Host "d3d11.dll exists (unknown or other mod). Removing/Overwriting..." -ForegroundColor Yellow
                Remove-Item $DllPath -Force
            }
        }
        
        Rename-Item -Path $DisabledPath -NewName $DllFileName -Force
        Write-Host "Burrito enabled as $DllFileName." -ForegroundColor Green
        return
    }
    
    Write-Host "No disabled file found. Downloading and installing Burrito..." -ForegroundColor Cyan
    Update-Burrito
}

# Function to update Burrito
function Update-Burrito {
    Write-Host "=== Burrito Update Script ===" -ForegroundColor Yellow
    Write-Host "Channel: $Channel" -ForegroundColor Cyan
    Write-Host ""
    
    if (-not (Test-Path $Gw2Path)) {
        Write-Error "Guild Wars 2 path not found: $Gw2Path"
        exit 1
    }
    
    Write-Host "GW2 Path: $Gw2Path" -ForegroundColor Cyan
    Write-Host ""
    
    # Get latest release info
    $releaseInfo = Get-LatestRelease -ReleaseChannel $Channel
    Write-Host "Release: $($releaseInfo.TagName)" -ForegroundColor Cyan
    
    # Determine temp directory
    $TempDir = [System.IO.Path]::GetTempPath()
    
    # Download the asset
    $TempAssetPath = Join-Path $TempDir $releaseInfo.Asset.name
    try {
        Get-RemoteFile -Url $releaseInfo.Asset.browser_download_url -OutputPath $TempAssetPath
    }
    catch {
        Write-Error "Failed to download release asset: $_"
        exit 1
    }
    
    # Extract or copy the dll
    $TempDllPath = $null
    if ($releaseInfo.IsZip) {
        Write-Host "Installing Burrito Overlay to $ResolvedInstallPath..." -ForegroundColor Cyan
        
        # Extract full zip to InstallPath
        if (-not (Test-Path $ResolvedInstallPath)) {
            New-Item -ItemType Directory -Path $ResolvedInstallPath -Force | Out-Null
        }
        
        try {
            # Extract everything
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($TempAssetPath, $ResolvedInstallPath, $true) # $true to overwrite
            Write-Host "Extracted Burrito to $ResolvedInstallPath" -ForegroundColor Green
            
            # Make executable
            $BurritoExe = Join-Path $ResolvedInstallPath "burrito.x86_64"
            if (Test-Path $BurritoExe) {
                chmod +x $BurritoExe
                Write-Host "Made $BurritoExe executable" -ForegroundColor Green
            } else {
                Write-Warning "Could not find burrito.x86_64 in extracted files"
            }
            
            # Find the DLL in the extracted files (usually in burrito_link/)
            $LinkDir = Join-Path $ResolvedInstallPath "burrito_link"
            $TempDllPath = Join-Path $LinkDir $DllFileName
            
            if (-not (Test-Path $TempDllPath)) {
                # Fallback search
                $TempDllPath = Get-ChildItem -Path $ResolvedInstallPath -Filter $DllFileName -Recurse | Select-Object -First 1 -ExpandProperty FullName
            }
        }
        catch {
            Write-Error "Failed to extract archive: $_"
            Remove-Item $TempAssetPath -ErrorAction SilentlyContinue
            exit 1
        }
    }
    else {
        $TempDllPath = $TempAssetPath
    }
    
    if (-not $TempDllPath -or -not (Test-Path $TempDllPath)) {
        Write-Error "d3d11.dll not found after extraction/download"
        Remove-Item $TempAssetPath -ErrorAction SilentlyContinue
        exit 1
    }
    
    # Determine target filename
    $TargetName = $DllFileName
    $Reason = "Default"
    
    if (Test-Path $ChainloadPath) {
        $TargetName = $ChainloadFileName
        $Reason = "Existing chainload found"
    }
    elseif (Test-Path $DllPath) {
        if (Test-Arcdps $DllPath) {
            $TargetName = $ChainloadFileName
            $Reason = "Arcdps detected at d3d11.dll"
        }
    }
    
    Write-Host "Targeting: $TargetName ($Reason)" -ForegroundColor Cyan
    $FinalPath = Join-Path $Gw2Path $TargetName
    
    # Get hash of downloaded file
    $DownloadedHash = Get-FileSHA256 -FilePath $TempDllPath
    Write-Host "Downloaded SHA256: $DownloadedHash" -ForegroundColor Gray
    
    # Get current hash
    $CurrentHash = if (Test-Path $FinalPath) {
        Get-FileSHA256 -FilePath $FinalPath
    } else {
        $null
    }
    
    if ($DownloadedHash -eq $CurrentHash) {
        Write-Host "$TargetName is already up to date!" -ForegroundColor Green
        
        # Even if DLL is up to date, try to update extra files if it's a zip
        if ($releaseInfo.IsZip) {
             Write-Host "Updating extra link files..." -ForegroundColor Cyan
             $LinkDir = Join-Path $ResolvedInstallPath "burrito_link"
             Expand-ExtraFiles -ZipPath $TempAssetPath -DestinationPath $Gw2Path
        }
        
        Remove-Item $TempAssetPath -ErrorAction SilentlyContinue
        Write-Host ""
        Write-Host "=== Update Complete ===" -ForegroundColor Green
        if ($releaseInfo.IsZip) {
             Write-Host "Run Burrito Overlay: $ResolvedInstallPath/burrito.x86_64" -ForegroundColor Magenta
             Write-Host "NOTE: If you see a black background, make sure your compositor supports transparency." -ForegroundColor Yellow
             Write-Host "      You may also need to force the game to Windowed Fullscreen mode." -ForegroundColor Yellow
        }
        exit 0
    }
    
    Write-Host "Updating $TargetName..." -ForegroundColor Yellow
    
    try {
        Copy-Item -Path $TempDllPath -Destination $FinalPath -Force
        Write-Host "Successfully installed $TargetName!" -ForegroundColor Green
        
        if ($releaseInfo.IsZip) {
             Write-Host "Installing extra link files..." -ForegroundColor Cyan
             $LinkDir = Join-Path $ResolvedInstallPath "burrito_link"
             Expand-ExtraFiles -ZipPath $TempAssetPath -DestinationPath $Gw2Path
        }
    }
    catch {
        Write-Error "Failed to install: $_"
        exit 1
    }
    finally {
        Remove-Item $TempAssetPath -ErrorAction SilentlyContinue
    }
    
    Write-Host ""
    Write-Host "=== Update Complete ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "=== Update Complete ===" -ForegroundColor Green
    if ($releaseInfo.IsZip) {
         Write-Host "Run Burrito Overlay: $ResolvedInstallPath/burrito.x86_64" -ForegroundColor Magenta
         
         # Linux Troubleshooting Checks (Mini version)
         if ($IsLinux) {
             $SessionType = $env:XDG_SESSION_TYPE
             if ($SessionType -eq "wayland") {
                 Write-Host "WARNING: Wayland detected. Transparency may fail." -ForegroundColor Yellow
             }
             Write-Host "If you have issues, run: ./burrito.ps1 Troubleshoot" -ForegroundColor Cyan
         }
    }
}

# Function to troubleshoot Linux issues
function Invoke-BurritoTroubleshoot {
    Write-Host "=== Burrito Linux Troubleshooter ===" -ForegroundColor Yellow
    Write-Host ""
    
    if (-not $IsLinux) {
        Write-Host "This function is designed for Linux systems." -ForegroundColor Gray
        return
    }

    # 1. Check Session Type
    $SessionType = $env:XDG_SESSION_TYPE
    Write-Host "1. Display Server: " -NoNewline
    if ($SessionType -eq "wayland") {
        Write-Host "$SessionType" -ForegroundColor Red
        Write-Host "   [!] Wayland often blocks overlay transparency for security." -ForegroundColor Yellow
        Write-Host "   -> Solution: Log out and switch to 'X11' or 'Xorg' session at login." -ForegroundColor Cyan
    }
    elseif ($SessionType -eq "x11" -or $SessionType -eq "tty") {
         Write-Host "$SessionType" -ForegroundColor Green
    }
    else {
         Write-Host "$SessionType (Unknown)" -ForegroundColor Yellow
    }
    Write-Host ""

    # 2. Check Compositor
    Write-Host "2. Compositor Status:"
    $Compositors = @("picom", "compton", "kwin_x11", "mutter", "gnome-shell", "xfwm4", "marco")
    $FoundCompositor = $false
    
    foreach ($comp in $Compositors) {
        if (Get-Process $comp -ErrorAction SilentlyContinue) {
            Write-Host "   [+] Found active compositor: $comp" -ForegroundColor Green
            $FoundCompositor = $true
            
            if ($comp -match "picom|compton") {
                 Write-Host "   [i] For Picom/Compton, you may need to allow shadows/transparency for Burrito." -ForegroundColor Gray
                 Write-Host "   -> Try adding to picom.conf: shadow-exclude = [ `"name = 'Burrito'`" ];" -ForegroundColor Cyan
            }
            break
        }
    }
    
    if (-not $FoundCompositor) {
        Write-Host "   [!] No common compositor found running." -ForegroundColor Red
        Write-Host "   Transparency REQUIRES a compositor on X11." -ForegroundColor Yellow
        Write-Host "   -> Solution: Install and run 'picom' (e.g., 'picom -b' in terminal)." -ForegroundColor Cyan
    }
    Write-Host ""

    # 3. Game Mode Warning
    Write-Host "3. Guild Wars 2 Settings:"
    Write-Host "   Ensure the game is in 'Windowed Fullscreen' mode." -ForegroundColor Cyan
    Write-Host "   (Exclusive Fullscreen often blocks overlays)" -ForegroundColor Gray
    Write-Host ""

    # 4. Alternative Launch Options
    Write-Host "4. Alternative Launch Options to try:"
    Write-Host "   Run these commands in your terminal:" -ForegroundColor Gray
    Write-Host "   a) Try GLES2 backend (sometimes fixes transparency):" -ForegroundColor Gray
    Write-Host "      $ResolvedInstallPath/burrito.x86_64 --video-driver GLES2" -ForegroundColor White
    Write-Host ""
    Write-Host "   b) Force windowed mode explicitly:" -ForegroundColor Gray
    Write-Host "      $ResolvedInstallPath/burrito.x86_64 --windowed --always-on-top" -ForegroundColor White
    Write-Host ""
}

# Main script logic
switch ($Action) {
    "Disable" { Disable-Burrito }
    "Enable" { Enable-Burrito }
    "Update" { Update-Burrito }
    "Troubleshoot" { Invoke-BurritoTroubleshoot }
}
