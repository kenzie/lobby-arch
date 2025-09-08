# Lobby Screen Arch Installer

This repository provides a **repeatable Arch Linux installer** for lobby screens, designed to display information for a sports team. It installs a base Arch system with **Wayland/Cage kiosk compositor**, sets up users, networking, and automatically runs a modular post-install script to configure the complete lobby display system.

---

## Features

- Automated Arch Linux base install
- User creation with default `lobby` user and hostname `lobby-screen`
- EFI + root partition setup (supports NVMe and SATA)
- Wayland/Cage kiosk compositor setup (replaced Hyprland for better reliability)
- NetworkManager + SSH enabled
- **Modular post-install system**:
  - Route 19 Plymouth boot splash screen
  - Automated lobby-display Vue.js app management
  - Service monitoring and automatic restart
  - Daily schedule (11:59 PM shutdown, 8:00 AM startup)
  - Automated system and project updates (2:00 AM daily)
  - Complete systemd service integration
- Fully idempotent and repeatable on new hardware

---

## Hardware Requirements

- Lenovo M75q-1 Tiny (16 GB RAM recommended)
- TV or monitor with HDMI (CEC optional)
- Ethernet connection recommended

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

```bash
# Full system setup (run automatically on first boot)
sudo ./scripts/lobby.sh setup

# Check system status
./scripts/lobby.sh status

# View recent logs
./scripts/lobby.sh logs

# List available modules
./scripts/lobby.sh list

# Update from GitHub repository
sudo ./scripts/lobby.sh sync

# Check for available updates
./scripts/lobby.sh check-updates

# Force update (bypass cache)
sudo ./scripts/lobby.sh sync --force

# Module-specific operations
sudo ./scripts/lobby.sh setup kiosk      # Setup specific module
sudo ./scripts/lobby.sh reset plymouth   # Reset specific module
sudo ./scripts/lobby.sh validate         # Validate all modules
```

### Module Structure

The system uses a modular architecture with the following components:

- **02-kiosk.sh** - Wayland/Cage compositor + Chromium kiosk setup
- **03-plymouth.sh** - Route 19 boot splash screen configuration  
- **04-auto-updates.sh** - Automated system and project updates
- **05-monitoring.sh** - Service health monitoring and restart
- **06-scheduler.sh** - Daily operation schedule (8 AM start, 11:59 PM stop)
- **99-cleanup.sh** - Final system cleanup and optimization

### Daily Schedule

The system operates on an automated schedule:
- **8:00 AM**: Start lobby-display and kiosk services
- **11:59 PM**: Stop all lobby services
- **2:00 AM**: Run system updates (during downtime)
