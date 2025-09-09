# Lobby Arch Linux Setup

This project contains **production-tested scripts** to automate the setup of an Arch Linux system for the Route 19 lobby display.

## Overview

After booting from the latest Arch Linux ISO on USB, these scripts will:
- Prepare Arch Linux with minimal prompts and AMD hardware support
- Install and configure all necessary software with proper error handling
- Set up a system that launches quickly with the Route 19 logo on boot
- Deploy the [lobby-display](https://github.com/kenzie/lobby-display.git) project in a Cage+Chromium kiosk

## System Requirements

**Tested Hardware:**
- Lenovo M75q-1 Tiny (16GB RAM, 256GB NVMe)
- AMD Ryzen processor with integrated graphics
- HDMI display connection
- Ethernet connection (required for installation)

### Boot Display
- Plymouth boot splash with Route 19 logo for professional startup

### Application Architecture
- **Cage (Wayland compositor)** - Minimal kiosk environment
- **Chromium browser** - Runs in full kiosk mode with hidden cursor
- **lobby-display Vue.js app** - Automatically built and served locally
- **No desktop environment** - Direct boot to kiosk for maximum performance

### Application Management
- **System services** manage all components with automatic restart
- **Health monitoring** tracks service status and resource usage
- **Error recovery** handles failures gracefully with restart limits
- **Professional display** with no visible cursor or browser UI

### Daily Schedule
- **8:00 AM**: Start lobby display and kiosk services
- **11:59 PM**: Shutdown all lobby services for maintenance
- **2:00 AM**: Automated system updates during downtime

### Update Management
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
3. Creates lobby user and configures services
4. Downloads and builds lobby-display Vue.js app
5. Configures Cage kiosk with Chromium browser
6. Sets up monitoring, scheduling, and maintenance
7. **Reboots directly into working kiosk**

## 🔧 System Management

**Global lobby command for all operations:**

```bash
# System health and diagnostics
sudo lobby health          # Comprehensive system check
sudo lobby status          # Quick service overview
sudo lobby logs            # View recent system logs

# Maintenance and updates  
sudo lobby sync            # Update scripts from GitHub
sudo lobby setup           # Re-run full system setup
sudo lobby validate        # Check all components
sudo lobby help            # Complete command reference
```

## Development Notes

- This project is being developed on a live test system, so local configuration changes need also be made in this git repository.
- Make sure the git repo is kept up to date with the local system files and vice versa when making changes to the live machine.
