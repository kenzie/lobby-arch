# Lobby Screen Arch Installer

This repository provides a **tested and reliable Arch Linux installer** for lobby screens, designed to display information for a sports team. It installs a base Arch system with **Cage (Wayland compositor)** running Chromium in kiosk mode, sets up users, networking, and automatically runs a modular post-install script to configure the complete lobby display system.

---

## Features

- **Fully automated** Arch Linux base install with AMD hardware support
- User creation with default `lobby` user and hostname `lobby-screen`
- EFI + root partition setup (supports NVMe and SATA drives)
- **Cage (Wayland compositor)** running Chromium in kiosk mode (no desktop environment)
- NetworkManager + SSH enabled with proper AMD graphics drivers
- **Modular post-install system**:
  - Route 19 Plymouth boot splash screen with logo
  - **lobby-display Vue.js app** automatic build and deployment
  - **Service monitoring** with automatic restart on failure
  - **Daily schedule**: 11:59 PM shutdown, 8:00 AM startup
  - **Automated updates**: System and project updates at 2:00 AM daily
  - **Complete systemd service integration** with proper error handling
- **Production tested** on Lenovo M75q-1 with 16GB RAM and 256GB NVMe
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

The installer automatically runs the post-install script on first boot, setting up all lobby components.

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

# Updates and maintenance
sudo lobby sync                          # Update scripts from GitHub repository
sudo lobby sync --force                  # Force update (bypass cache)
sudo lobby check-updates                 # Check for available updates

# Module-specific operations  
sudo lobby setup kiosk                   # Setup specific module
sudo lobby reset plymouth                # Reset specific module
sudo lobby help                          # Full command reference
```

### Module Structure

The system uses a modular architecture with the following components:

- **02-kiosk.sh** - Cage (Wayland compositor) + Chromium kiosk with cursor hiding
- **03-plymouth.sh** - Route 19 boot splash screen with logo display
- **04-auto-updates.sh** - Automated system and project updates with error recovery
- **05-monitoring.sh** - Service health monitoring with automatic restart
- **06-scheduler.sh** - Daily operation schedule (8:00 AM start, 11:59 PM stop)  
- **99-cleanup.sh** - Global command setup, log rotation, and system optimization

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
