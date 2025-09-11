# Lobby Arch Linux Setup

This project contains **production-tested and reliable scripts** to automate the setup of an Arch Linux system for the Route 19 lobby display with animated Plymouth boot theme and git-based synchronization.

## Overview

After booting from the latest Arch Linux ISO on USB, these scripts will:
- Prepare Arch Linux with minimal prompts and AMD hardware support
- Install and configure all necessary software with robust error handling
- Set up a system with animated Plymouth boot theme (Route 19 logo + loading dots)
- Run post-install setup during installation (not first boot) for immediate functionality
- Deploy the [lobby-display](https://github.com/kenzie/lobby-display.git) project in a Hyprland+Chromium kiosk
- Use git-based synchronization for reliable updates and version control

## System Requirements

**Tested Hardware:**
- Lenovo M75q-1 Tiny (16GB RAM, 256GB NVMe)
- AMD Ryzen processor with integrated graphics
- HDMI display connection
- Ethernet connection (required for installation)

### Boot Display
- Animated Plymouth boot splash with Route 19 logo and cycling loading dots
- Smooth transition from boot animation to kiosk display

### Application Architecture
- **Hyprland (Wayland compositor)** - High-performance kiosk environment
- **Chromium browser** - Runs in full kiosk mode with hidden cursor
- **lobby-display Vue.js app** - Automatically built and served locally
- **No desktop environment** - Direct boot to kiosk for maximum performance
- **VT Management** - Kiosk on VT2, admin TTY on VT1
- **Fast Boot** - Optimized 8-15 second boot time with Plymouth animation

### Application Management  
- **Arch Linux approach** - Auto-login + user systemd services (no complex system service dependencies)
- **User services** manage display and kiosk with automatic restart and proper ordering
- **Health monitoring** tracks service status and resource usage
- **Error recovery** handles failures gracefully with restart limits
- **Professional display** with no visible cursor or browser UI

### Daily Schedule
- **8:00 AM**: Start lobby display and kiosk services
- **11:59 PM**: Shutdown all lobby services for maintenance
- **2:00 AM**: Automated system updates during downtime

### Update Management
- **Git-based synchronization** for reliable script updates with version control
- **Automatic updates** for Arch Linux packages, lobby-arch scripts, and lobby-display app
- **Error handling** with retry logic and fallback strategies
- **Log rotation** prevents disk space issues
- **Update validation** ensures system integrity

## 🚀 Installation

**Single command installation:**

```bash
# Download and run installer
curl -sSL https://raw.githubusercontent.com/kenzie/lobby-arch/main/arch-install.sh -o /tmp/arch-install.sh
chmod +x /tmp/arch-install.sh
/tmp/arch-install.sh
```

**What happens automatically:**
1. Partitions disk and installs Arch Linux base system
2. Installs AMD drivers and required packages
3. Clones lobby-arch repository as proper git repository for reliable updates
4. Runs chroot-compatible post-install setup during installation
5. Creates lobby user and configures auto-login (Arch Linux way)
6. Downloads and builds lobby-display Vue.js app
7. Configures animated Plymouth theme with Route 19 logo
8. Sets up user systemd services for display and Hyprland kiosk
9. Configures monitoring, scheduling, and maintenance
10. Applies boot optimizations for 8-15 second boot time
11. **Reboots directly into working animated kiosk with clean boot process**

## 🔧 System Management

**Global lobby command for all operations:**

```bash
# System health and diagnostics
sudo lobby health          # Comprehensive system check
sudo lobby status          # Quick service overview
sudo lobby logs            # View recent system logs

# Maintenance and updates (git-based)
sudo lobby sync [--main]   # Update scripts from GitHub (default: latest tag, --main for main branch)
sudo lobby setup           # Re-run full system setup
sudo lobby validate        # Check all components
sudo lobby help            # Complete command reference
```

### Repository Structure
```
lobby-arch/
├── lobby.sh              # Main management script
├── post-install.sh       # Installation orchestrator
├── modules/              # Configuration modules
│   ├── 02-kiosk.sh
│   ├── 03-plymouth.sh
│   ├── 04-auto-updates.sh
│   ├── 05-monitoring.sh
│   ├── 06-scheduler.sh
│   └── 99-cleanup.sh
└── configs/              # Configuration templates
```

## Development Notes

- This project is being developed on a live test system, so local configuration changes need also be made in this git repository.
- Make sure the git repo is kept up to date with the local system files and vice versa when making changes to the live machine.
