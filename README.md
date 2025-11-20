# Guild Wars 2 Mod Scripts for Linux

Scripts to manage Guild Wars 2 mods and overlays on Linux (Steam/Proton).

## Overview

This repository contains PowerShell scripts to automate the installation and management of:
- **arcdps** - DPS meter and combat statistics overlay
- **Burrito** - Marker pack overlay and trail visualization tool

These scripts are designed for Guild Wars 2 running on Linux via Steam Proton.

## Requirements

- **PowerShell 7** (`pwsh`)
- **Steam** (with Guild Wars 2 installed)
- **Guild Wars 2**

## Usage

### arcdps Management

arcdps acts as a `d3d11.dll` proxy.

**Install or Update:**
```bash
pwsh ./arcdps.ps1 Update
```

**Enable or Disable:**
```bash
pwsh ./arcdps.ps1 Enable   # Renames d3d11.dll.arcdps -> d3d11.dll
pwsh ./arcdps.ps1 Disable  # Renames d3d11.dll -> d3d11.dll.arcdps
```

### Burrito Management

Burrito acts as an overlay. It supports chainloading if arcdps is already present.

**Install or Update:**
```bash
pwsh ./burrito.ps1 Update              # Update to latest stable release
pwsh ./burrito.ps1 Update -Channel next # Update to latest preview release
```

**Enable or Disable:**
```bash
pwsh ./burrito.ps1 Enable   # Enables Burrito
pwsh ./burrito.ps1 Disable  # Disables Burrito (renames to .burrito)
```

**Troubleshooting:**
If you have issues with transparency or the overlay not showing up:
```bash
pwsh ./burrito.ps1 Troubleshoot
```

**Release Channels:**
- `stable` (default) - Verified stable releases.
- `next` - Preview/pre-release builds (latest features, potentially unstable).

## Technical Notes

- **Chainloading**:
  - If `d3d11.dll` is missing or is not arcdps, Burrito installs as `d3d11.dll`.
  - If arcdps is detected at `d3d11.dll`, Burrito automatically installs as `arcdps_burrito.dll` (chainloaded by arcdps).
- **Overlay Transparency**:
  - On Linux, overlay transparency requires a compositor (e.g., `picom`) if running on X11.
  - Wayland sessions may restrict transparency for security reasons; X11 is recommended for overlays.
  - Game must be in **Windowed Fullscreen** mode.

## Files

- `arcdps.ps1` - Manager for arcdps
- `burrito.ps1` - Manager for Burrito

## Resources

- **arcdps**: [deltaconnected.com/arcdps](https://www.deltaconnected.com/arcdps/)
- **Burrito**: [github.com/AsherGlick/Burrito](https://github.com/AsherGlick/Burrito)
