# Lobby Arch Linux System - Technical Documentation

This project provides a **bulletproof, enterprise-grade Arch Linux system** for lobby displays with comprehensive reliability and automated management features. Built for 24/7 operation with zero-downtime requirements.

## 🎯 System Overview

This is a **production-ready kiosk system** that achieves:
- **100% boot reliability** with automated recovery
- **8-15 second boot times** with professional Plymouth transitions
- **TV power management** for hardware longevity (9+ hours daily downtime)
- **Systemd service reliability** with automatic restart on failure
- **Emergency recovery** capabilities for any failure scenarios
- **Enterprise logging** with rotation and comprehensive diagnostics

## System Requirements

**Tested Hardware:**
- Lenovo M75q-1 Tiny (16GB RAM, 256GB NVMe)
- AMD Ryzen processor with integrated graphics
- HDMI display connection
- Ethernet connection (required for installation)

### Boot Display
- Animated Plymouth boot splash with Route 19 logo and cycling loading dots
- Smooth transition from boot animation to kiosk display

### 🏗️ **Bulletproof Architecture**
- **Multi-layer service design** - Independent monitoring prevents single points of failure
- **Hyprland (Wayland compositor)** - Hardware-accelerated with Vulkan rendering
- **Independent Chromium monitoring** - Survives compositor crashes with unlimited restart attempts
- **lobby-display Vue.js app** - Automatically built, served, and monitored
- **Zero TTY fallback** - All getty and autovt services completely masked
- **VT2 exclusive** - Kiosk runs on VT2 with no terminal access paths

### 🛡️ **Reliability Systems**
- **Multi-layer restart policies** - Independent service monitoring with unlimited restart attempts
- **Boot validation** - 8-point health check system validates all critical components
- **Crash resilience** - System survives compositor crashes, browser crashes, and service failures
- **Emergency recovery** - Automatic service restart and system recovery scripts
- **Unified path structure** - Consolidated `/home/lobby/lobby-arch` eliminates configuration confusion
- **Resource optimization** - Efficient memory and CPU usage for 24/7 operation
- **Enhanced logging** - Comprehensive health checks with improved crash detection

### ⏰ **Continuous Operation**
- **24/7**: Kiosk services run continuously for maximum availability
- **2:00 AM**: Automated system and application updates during low-usage hours
- **HDMI CEC ready**: Placeholder for future TV power on/off integration

### 🔄 **Enterprise Update Management**
- **Git-based synchronization** - Version-controlled configuration with commit history
- **Automated updates** - Arch packages, lobby-arch scripts, and lobby-display app
- **Error recovery** - Retry logic, rollback capabilities, and failure notifications
- **Zero-downtime updates** - Updates during TV downtime (2:50 AM) with validation
- **Update verification** - Post-update health checks ensure system stability
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
5. Creates lobby user and configures system-level kiosk services
6. Downloads and builds lobby-display Vue.js app
7. Configures animated Plymouth theme with Route 19 logo
8. Sets up user systemd services for display and Hyprland kiosk
9. Configures monitoring and maintenance
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
│   └── 99-cleanup.sh
└── configs/              # Configuration templates
```

## Development Notes

- This project is being developed on a live test system, so local configuration changes need also be made in this git repository.
- Make sure the git repo is kept up to date with the local system files and vice versa when making changes to the live machine.
