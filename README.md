# Lobby Screen Arch Linux System

This repository provides a **bulletproof, production-ready Arch Linux system** for lobby screens, designed to display information for a sports team. It installs a base Arch system with **Hyprland (Wayland compositor)** running Chromium in kiosk mode, featuring **automated Plymouth boot themes** with Route 19 logo and comprehensive reliability systems.

---

## ✨ Key Features

### 🚀 **Bulletproof Boot Reliability**
- **Zero TTY fallback risk** - All getty services completely masked
- **Automated recovery** - Services restart on failure with systemd reliability
- **Boot validation** - Comprehensive 8-point health checks every 30 seconds
- **Plymouth integration** - Enhanced timing waits for full application launch

### 🖥️ **Modern Modular Kiosk Architecture**
- **Independent systemd services** - Compositor, app, and browser run as separate services for maximum reliability
- **Hyprland (Wayland compositor)** - Optimized for GPU acceleration with ANGLE support
- **Independent service lifecycle** - Components can restart independently without system-wide failures
- **ANGLE GPU acceleration** - Hardware-accelerated animations via OpenGL ES with native Wayland
- **Vue.js lobby-display app** - Automatically built and served locally with resource limits
- **No desktop environment** - Direct boot to kiosk for maximum performance

### ⚡ **Performance Optimized**
- **8-15 second boot time** - Optimized service dependencies and parallel loading
- **Resource efficient** - ~1.7GB total memory usage in active mode
- **TV power management** - Plymouth downtime mode saves 90% resources (11:59 PM - 8:00 AM)
- **Hardware acceleration** - ANGLE GPU acceleration with OpenGL ES for smooth animations

### 🔧 **Enterprise Management**
- **Git-based synchronization** - Version-controlled configuration with unified `/home/lobby/lobby-arch` path
- **Automated updates** - System and application updates at 2:50 AM with error recovery
- **Multi-layer restart policies** - Independent service monitoring ensures maximum uptime
- **Professional logging** - Comprehensive logs with rotation and automated cleanup
- **Crash resilience** - System survives compositor crashes, browser crashes, and service failures

---

## Hardware Requirements

- **Lenovo M75q-1 Tiny** (tested with 16GB RAM, 256GB NVMe)
- Any AMD Ryzen system with integrated graphics
- TV or monitor with HDMI connection
- **Ethernet connection required** during installation

---

## Pre-Install

1. Boot the target machine using an **Arch Linux ISO** on USB.
2. Connect Ethernet and ensure internet is available.

---

## Installation Steps

### 1. Start the Arch installer from USB

Boot into the Arch ISO and open a terminal.

### 2. Download and run the installer script

```bash
# Download main installer
curl -sSL https://raw.githubusercontent.com/kenzie/lobby-arch/main/install.sh -o /tmp/install.sh
chmod +x /tmp/install.sh

# Run installer
/tmp/install.sh
```

### 3. Automatic post-install setup

The installer automatically runs the post-install script **during installation** (not first boot), setting up all lobby components. The system boots directly into a working kiosk with animated Plymouth theme.

---

## System Management

After installation, use the lobby management script for system operations:

### 🛠️ System Management Commands

The system includes a **global `lobby` command** for easy management:

```bash
# System diagnostics and monitoring
sudo lobby health                        # Comprehensive system health check with 20+ validations
sudo lobby status                        # Real-time status of all modules (✓ OK / ✗ FAILED)
sudo lobby logs                          # View recent system logs with filtering

# System management  
sudo lobby setup                         # Full bulletproof system setup
sudo lobby validate                      # Validate all modules (kiosk, plymouth, auto-updates, etc.)
sudo lobby sync && sudo lobby setup      # Update from git and refresh configuration

# Module-specific operations
sudo lobby setup compositor              # Configure Hyprland compositor with ANGLE GPU acceleration
sudo lobby setup app                     # Configure Vue.js lobby display service
sudo lobby setup browser                 # Configure Chromium browser with ANGLE acceleration
sudo lobby setup plymouth                # Configure Route 19 boot theme with enhanced timing
sudo lobby reset [module]                # Reset specific module to defaults
```

### Module Structure

The system uses a modular architecture with the following components:

- **modules/10-plymouth.sh** - Route 19 boot splash screen with logo and animated loading dots
- **modules/20-compositor.sh** - Hyprland compositor service with ANGLE GPU acceleration
- **modules/30-app.sh** - Vue.js lobby display application with resource limits
- **modules/40-browser.sh** - Chromium browser service with ANGLE GPU acceleration
- **modules/50-auto-updates.sh** - Automated system and project updates with error recovery
- **modules/90-cleanup.sh** - Global command setup, log rotation, and system optimization

### Automated Maintenance

The system runs automated maintenance:
- **2:00 AM**: System updates (Arch packages, lobby-arch, and lobby-display)
- **Continuous**: 24/7 operation with automatic service recovery

### System Features

- **No cursor display** - Professional kiosk appearance
- **Automatic crash recovery** - Services restart on failure with intelligent limits
- **System logs** - Centralized logging with systemd journal management
- **Log rotation** - Automatic cleanup to prevent disk space issues
- **AMD hardware optimization** - Includes microcode updates and graphics drivers
- **Network resilience** - Handles connectivity issues during updates and operations

---

## Troubleshooting

### Common Issues

**Plymouth theme stays on screen after boot:**
```bash
# Check if kiosk services are running
sudo lobby health

# Switch to kiosk display (VT2)
sudo chvt 2

# Switch back to TTY for admin (VT1)  
sudo chvt 1
```

**Updates failing:**
```bash
# Check git repository status
sudo lobby sync

# Force update if needed
sudo lobby sync --force
```

**Service failures:**
```bash
# Check specific service status
sudo systemctl status lobby-compositor.service lobby-app.service lobby-browser.service

# Restart services if needed
sudo lobby setup compositor
sudo lobby setup app
sudo lobby setup browser
```

### System Architecture

The system uses **Hyprland (Wayland compositor)** with modular service management:

**🔧 Independent Service Architecture:**
```
lobby-compositor.service  → Hyprland Wayland compositor
lobby-app.service        → Vue.js app (port 8080, memory limited)
lobby-browser.service    → Chromium browser (waits for compositor + app)
```

**🛡️ Production-Ready Design Principles:**
- **Modular architecture** - Each service (compositor, app, browser) runs independently
- **No cascade failures** - Compositor crashes don't affect browser or app services
- **Resource constraints** - App service has memory limits and security restrictions
- **Dependency management** - Browser waits for compositor and app to be healthy before starting
- **Hyprland with ANGLE** - Wayland compositor optimized for GPU acceleration and smooth animations
- **Unified path structure** - All components use `/home/lobby/lobby-arch`
- **Git-based updates** - Reliable synchronization with proper repository structure
- **VT switching** - Kiosk display on VT2, TTY1 available for admin access
- **Fast boot optimization** - 8-15 second boot time with Plymouth animation
- **Enterprise logging** - Comprehensive health checks and crash detection

### Support

For issues with the installer or system setup, check the logs:
```bash
sudo lobby logs
sudo lobby health
sudo journalctl -b | grep lobby
```
