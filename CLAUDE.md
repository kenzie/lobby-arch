# Lobby Arch Linux Setup

This project contains scripts to automate the setup of an Arch Linux system for the Route 19 lobby display.

## Overview

After booting from the latest Arch Linux ISO on USB, these scripts will:
- Prepare Arch Linux with minimal prompts
- Install and configure all necessary software
- Set up a system that launches quickly with the Route 19 logo on boot
- Prepare the machine to run the [lobby-display](https://github.com/kenzie/lobby-display.git) project in a Chromium kiosk

## System Requirements

### Boot Display
- Show Route 19 logo on boot for quick visual feedback

## Application Setup
- Install Cage (Wayland compositor) and dependencies
- Configure Cage to start automatically on boot
- Configure Cage to run Chromium in kiosk mode displaying the lobby-display Vue.js app

### Application Management
- Monitor Cage, Chromium kiosk, and Vue.js app to ensure continuous operation
- Automatic restart if a component fails

### Daily Schedule
- **11:59 PM**: Shutdown Chromium kiosk and Vue app
- **8:00 AM**: Restart Vue app and Chromium kiosk

### Update Management
- Daily updates for:
  - Arch Linux system packages
  - lobby-arch project
  - lobby-display project
- Updates run during non-operational hours at 2:00 AM

### 🚀 Usage

```bash
# Download main installer
curl -sSL https://raw.githubusercontent.com/kenzie/lobby-arch/main/arch-install.sh -o /tmp/arch-install.sh
chmod +x /tmp/arch-install.sh

# Run installer
/tmp/arch-install.sh
```

## Maintenance

```bash
# Get help with post install maintenance and updates
sudo lobby help
```

## Development Notes

- This project is being developed on a live test system, so local configuration changes need also be made in this git repository.
- Make sure the git repo is kept up to date with the local system files and vice versa when making changes to the live machine.
