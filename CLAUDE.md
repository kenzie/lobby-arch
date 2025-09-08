# Lobby Arch Linux Setup

This project contains scripts to automate the setup of an Arch Linux system for the Route 19 lobby display.

## Overview

After booting from the latest Arch Linux ISO on USB, these scripts will:
- Prepare Arch Linux with minimal prompts
- Configure and install necessary software
- Set up a system that launches quickly with the Route 19 logo on boot
- Prepare the machine to run the [lobby-display](https://github.com/kenzie/lobby-display.git) project in a Chromium kiosk

## System Requirements

### Boot Display
- Show Route 19 logo on boot for quick visual feedback

### Application Management
- Run lobby-display Vue.js app in Chromium kiosk mode
- Monitor both Chromium kiosk and Vue.js app to ensure continuous operation
- Automatic restart if either component fails

### Daily Schedule
- **11:59 PM**: Shutdown Chromium kiosk and Vue app
- **8:00 AM**: Restart Vue app and Chromium kiosk

### Update Management
- Daily updates for:
  - Arch Linux system packages
  - lobby-arch project
  - lobby-display project
- Updates run during non-operational hours (between 11:59 PM and 8:00 AM)

## Implementation Status

### ✅ Completed Components

- **Kiosk System**: X11 + Chromium kiosk setup (replaced Hyprland)
- **Boot Display**: Plymouth with Route 19 logo
- **Application Management**: Systemd services for lobby-display and kiosk
- **Monitoring**: Automated restart system for failed services
- **Daily Schedule**: 11:59 PM shutdown, 8:00 AM startup via systemd timers  
- **Automated Updates**: Daily updates (2 AM) for Arch, lobby-arch, and lobby-display
- **Modular Architecture**: Clean, maintainable module-based setup

### 🗂️ Module Structure

- `02-kiosk.sh` - Chromium kiosk and lobby-display setup
- `03-plymouth.sh` - Route 19 boot splash screen
- `04-auto-updates.sh` - System and project updates
- `05-monitoring.sh` - Service health monitoring
- `06-scheduler.sh` - Daily operation schedule
- `99-cleanup.sh` - Final system cleanup

### 🚀 Usage

After Arch installation, run:
```bash
./post-install.sh
```

This will configure all lobby components automatically.

## Architecture Changes

**Removed Components:**
- Auto-login (unnecessary for service-based approach)
- Hyprland (replaced with minimal X11 for better reliability)

**Benefits:**
- Simplified, more reliable kiosk operation
- Better service monitoring and automatic recovery
- Easier maintenance and updates

## Development Notes

This project is developed on a test system with local changes being made alongside git project updates.
- Make sure the git repo is kept up to date with the local system files and vice versa when making changes to the live machine