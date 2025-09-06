# Lobby Screen Arch Installer

This repository provides a **repeatable Arch Linux installer** for lobby screens, designed to display information for a sports team. It installs a base Arch system with **Hyprland**, sets up users, networking, and automatically runs a post-install script to install Plymouth with a Route 19 branded boot splash.

---

## Features

- Automated Arch Linux base install
- User creation with default `lobby` user and hostname `lobby-screen`
- EFI + root partition setup (supports NVMe and SATA)
- Hyprland installed with basic desktop environment
- NetworkManager + SSH enabled
- **Automatic first-boot post-install**:
  - Installs AUR helper `yay`
  - Installs Plymouth and sets up Route 19 splash theme
  - Cleans itself after running
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
