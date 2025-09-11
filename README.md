# Lobby Screen Arch Linux System

This repository provides a **bulletproof, production-ready Arch Linux system** for lobby screens, designed to display information for a sports team. It installs a base Arch system with **Hyprland (Wayland compositor)** running Chromium in kiosk mode, featuring **automated Plymouth boot themes** with Route 19 logo and comprehensive reliability systems.

---

## ✨ Key Features

### 🚀 **Bulletproof Boot Reliability**
- **Zero TTY fallback risk** - All getty services completely masked
- **Automated recovery** - Services restart on failure with health monitoring
- **Boot validation** - Comprehensive 8-point health checks every 30 seconds
- **Plymouth integration** - Enhanced timing waits for full application launch
- **Emergency recovery** - Automated failsafe scripts for any boot failures

### 🖥️ **Modern Kiosk Architecture**
- **System-level services** - Professional systemd service architecture
- **Hyprland (Wayland compositor)** - Hardware-accelerated, minimal resource usage
- **Chromium kiosk mode** - Full-screen with hidden cursor and professional display
- **lobby-display Vue.js app** - Automatically built and served locally
- **No desktop environment** - Direct boot to kiosk for maximum performance

### ⚡ **Performance Optimized**
- **8-15 second boot time** - Optimized service dependencies and parallel loading
- **Resource efficient** - ~1.7GB total memory usage in active mode
- **TV power management** - Plymouth downtime mode saves 90% resources (11:59 PM - 8:00 AM)
- **Hardware acceleration** - Full AMD GPU support with Vulkan renderer

### 🔧 **Enterprise Management**
- **Git-based synchronization** - Version-controlled configuration and updates
- **Automated updates** - System and application updates at 2:50 AM with error recovery
- **Health monitoring** - Real-time service status with automated alerts
- **Professional logging** - Comprehensive logs with rotation and cleanup
- **TV longevity** - Daily 9+ hour downtime cycle extends hardware lifespan

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
curl -sSL https://raw.githubusercontent.com/kenzie/lobby-arch/main/arch-install.sh -o /tmp/arch-install.sh
chmod +x /tmp/arch-install.sh

# Run installer
/tmp/arch-install.sh
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

# Reliability and validation
sudo /home/lobby/lobby-arch/scripts/boot-validator.sh validate    # 8-point boot health check
sudo /home/lobby/lobby-arch/scripts/boot-validator.sh stress 10   # Reliability stress test
sudo /home/lobby/lobby-arch/scripts/emergency-recovery.sh         # Emergency kiosk recovery

# System management  
sudo lobby setup                         # Full bulletproof system setup
sudo lobby validate                      # Validate all modules (kiosk, plymouth, monitoring, etc.)
sudo lobby sync && sudo lobby setup      # Update from git and refresh configuration

# Module-specific operations
sudo lobby setup kiosk                   # Configure bulletproof kiosk with monitoring
sudo lobby setup plymouth                # Configure Route 19 boot theme with enhanced timing
sudo lobby setup monitoring              # Install health monitoring and auto-recovery
sudo lobby reset [module]                # Reset specific module to defaults
```

### Module Structure

The system uses a modular architecture with the following components:

- **modules/02-kiosk.sh** - Auto-login + user services for Hyprland (Wayland compositor) + Chromium kiosk with cursor hiding
- **modules/03-plymouth.sh** - Route 19 boot splash screen with logo and animated loading dots
- **modules/04-auto-updates.sh** - Automated system and project updates with error recovery
- **modules/05-monitoring.sh** - Service health monitoring with automatic restart
- **modules/06-scheduler.sh** - Daily operation schedule (8:00 AM start, 11:59 PM stop)  
- **modules/99-cleanup.sh** - Global command setup, log rotation, and system optimization

### Daily Schedule

The system operates on an automated schedule:
- **8:00 AM**: Start lobby-display and kiosk services
- **11:59 PM**: Stop all lobby services for maintenance window
- **2:00 AM**: Run system updates (Arch packages, lobby-arch, and lobby-display)

### System Features

- **No cursor display** - Professional kiosk appearance
- **Automatic crash recovery** - Services restart on failure with intelligent limits
- **Resource monitoring** - Disk space, memory usage, and performance tracking
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
sudo systemctl status lobby-kiosk.service

# Restart services if needed
sudo lobby setup kiosk
```

### System Architecture

The system uses **Hyprland (Wayland compositor)** with Arch Linux best practices:
- **No desktop environment** - Direct boot to kiosk via auto-login
- **User systemd services** - Clean service management without complex system dependencies  
- **Git-based updates** - Reliable synchronization with proper repository structure
- **Chroot-compatible setup** - Installation completes during arch-install.sh execution
- **VT switching** - Kiosk display on VT2, TTY1 available for admin access
- **Fast boot optimization** - 8-15 second boot time with Plymouth animation
- **Portable configuration** - Dynamic UID detection for cross-system compatibility

### Support

For issues with the installer or system setup, check the logs:
```bash
sudo lobby logs
sudo lobby health
sudo journalctl -b | grep lobby
```
