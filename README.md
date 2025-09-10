# Lobby Screen Arch Installer

This repository provides a **production-tested and reliable Arch Linux installer** for lobby screens, designed to display information for a sports team. It installs a base Arch system with **Cage (Wayland compositor)** running Chromium in kiosk mode, featuring an **animated Plymouth boot theme** with Route 19 logo and loading dots. The installer uses **git-based synchronization** for reliable updates and runs a **chroot-compatible post-install system** during installation for immediate functionality.

---

## Features

- **Fully automated** Arch Linux base install with AMD hardware support and robust error handling
- User creation with default `lobby` user and hostname `lobby-screen`
- EFI + root partition setup (supports NVMe and SATA drives)
- **Cage (Wayland compositor)** running Chromium in kiosk mode (no desktop environment)
- **Animated Plymouth boot theme** with Route 19 logo and cycling loading dots
- NetworkManager + SSH enabled with proper AMD graphics drivers
- **Git-based synchronization** for reliable script updates and version control
- **Chroot-compatible post-install system** that runs during installation (not first boot):
  - Route 19 Plymouth boot splash with animation that transitions smoothly to kiosk
  - **lobby-display Vue.js app** automatic build and deployment
  - **Service monitoring** with automatic restart on failure and intelligent limits
  - **Daily schedule**: 11:59 PM shutdown, 8:00 AM startup for power management
  - **Automated updates**: System and project updates at 2:00 AM daily with error recovery
  - **Arch Linux service approach** with auto-login + user systemd services (eliminates complex system service dependencies)
- **Production tested** on Lenovo M75q-1 with 16GB RAM and 256GB NVMe
- **Immediate functionality** - boots directly into working kiosk after installation
- Fully idempotent and repeatable on new AMD hardware

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

### Available Commands

The system includes a **global `lobby` command** for easy management:

```bash
# System diagnostics and monitoring
sudo lobby health                        # Comprehensive system health check
sudo lobby status                        # Quick status overview
sudo lobby logs                          # View recent logs

# System management
sudo lobby setup                         # Full system setup (run automatically on first boot)  
sudo lobby validate                      # Validate all modules and services
sudo lobby list                          # List available modules

# Updates and maintenance (git-based)
sudo lobby sync                          # Update scripts from GitHub repository using git pull
sudo lobby sync --force                  # Force update (bypass cache)
sudo lobby check-updates                 # Check for available updates using git fetch

# Module-specific operations  
sudo lobby setup kiosk                   # Setup specific module
sudo lobby reset plymouth                # Reset specific module
sudo lobby help                          # Full command reference
```

### Module Structure

The system uses a modular architecture with the following components:

- **modules/02-kiosk.sh** - Auto-login + user services for Cage (Wayland compositor) + Chromium kiosk with cursor hiding
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

# Manually transition to kiosk if needed
sudo systemctl isolate graphical.target
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

The system uses **Wayland/Cage compositor** with Arch Linux best practices:
- **No desktop environment** - Direct boot to kiosk via auto-login
- **User systemd services** - Clean service management without complex system dependencies  
- **Git-based updates** - Reliable synchronization with proper repository structure
- **Chroot-compatible setup** - Installation completes during arch-install.sh execution

### Support

For issues with the installer or system setup, check the logs:
```bash
sudo lobby logs
sudo lobby health
sudo journalctl -b | grep lobby
```
