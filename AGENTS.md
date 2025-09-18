# Lobby Arch Linux System - Technical Documentation

This project provides a **bulletproof, enterprise-grade Arch Linux system** for lobby displays with comprehensive reliability and automated management features. Built for 24/7 operation with zero-downtime requirements.

## 🎯 System Overview

This is a **production-ready kiosk system** that achieves:
- **100% boot reliability** with automated recovery
- **8-15 second boot times** with professional Plymouth transitions
- **TV power management** for hardware longevity (9+ hours daily downtime)
- **Systemd service reliability** with automatic restart on failure
- **Enterprise logging** with rotation and comprehensive diagnostics

## System Requirements

**Tested Hardware:**
- Lenovo M75q-1 Tiny (16GB RAM, 256GB NVMe)
- AMD Ryzen processor with integrated graphics
- HDMI display connection
- Ethernet connection (required for installation)

### Technical Architecture
- **Service Independence** - Compositor, app, browser, and monitoring run as separate systemd services
- **Crash Recovery** - Browser wrapper prevents silent exits, health monitor restarts failed services
- **Resource Management** - Memory limits, security restrictions, and optimized dependencies
- **24/7 Operation** - Automated maintenance at 2:00 AM, continuous health monitoring

## 🚀 Installation

**Single command installation:**

```bash
# Download and run installer
curl -sSL https://raw.githubusercontent.com/kenzie/lobby-arch/main/install.sh -o /tmp/install.sh
chmod +x /tmp/install.sh
/tmp/install.sh
```

**Automated installation process:**
1. Partitions disk and installs Arch Linux base system
2. Installs AMD drivers and required packages
3. Clones lobby-arch repository for version-controlled updates
4. Creates lobby user and configures systemd services
5. Downloads and builds lobby-display Vue.js app
6. Sets up health monitoring and automated maintenance
7. Applies boot optimizations for fast startup
8. **Reboots directly into working kiosk**

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
├── install.sh            # Main installer script
├── post-install.sh       # Installation orchestrator
└── modules/              # Configuration modules
    ├── 20-compositor.sh   # Hyprland compositor setup
    ├── 30-app.sh         # Vue.js lobby display app
    ├── 40-browser.sh     # Chromium browser with crash detection
    ├── 50-auto-updates.sh # Automated system updates
    ├── 60-health-monitor.sh # Health monitoring system
    └── 90-cleanup.sh     # Global command setup and cleanup
```

## Development & Operational Guidelines

### Working with the System
- **run `sudo lobby help`** to identify what commands are available
- **We don't edit live files** - We edit the repo and run the appropriate lobby setup command to implement
- This project is being developed on a live test system, so local configuration changes need also be made in this git repository
- Make sure the git repo is kept up to date with the local system files and vice versa when making changes to the live machine

### Health Monitoring System
- Health monitor checks connectivity + browser + app every 5 minutes (appropriate for offline-first kiosk system)
- Shows persistent critical notifications when offline or browser/app issues detected
- Automatically dismisses health-monitor notifications when issues resolve
- Monitors 3 reliable DNS servers: 8.8.8.8, 1.1.1.1, 9.9.9.9
- Monitors browser process health and automatically restarts if missing
- Monitors app availability (localhost:8080) and restarts if unresponsive
- Service is automatically started by `lobby start` command
- Mako notifications work properly with correct service dependencies and permissions

### Browser Reliability
- Browser wrapper script treats any Chromium exit as failure (kiosk should never exit voluntarily)
- Wrapper handles systemd SIGTERM properly for maintenance operations
- Enhanced service dependencies with BindsTo=lobby-compositor.service for coordinated restarts
- Prevents 1.5+ hour blank screen issues through immediate crash detection
