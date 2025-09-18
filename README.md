# Lobby Screen Arch Linux System

A **bulletproof, production-ready Arch Linux system** for lobby screens, designed to display information for a sports team. Features Hyprland compositor running Chromium in kiosk mode with comprehensive reliability systems.

---

## ✨ Key Benefits

- **🚀 Bulletproof Reliability** - Automated crash detection, health monitoring, and service recovery
- **⚡ Fast Performance** - 10-second boot time with GPU acceleration and resource optimization  
- **🔧 Enterprise Ready** - Git-based updates, professional logging, and 24/7 automated maintenance
- **🖥️ Modern Architecture** - Wayland compositor with independent modular services

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

The installer automatically runs the post-install script during installation, setting up all lobby components. The system boots directly into a working kiosk.

---

## System Architecture

The system uses **Hyprland (Wayland compositor)** with independent modular services:

### 🔧 Service Architecture
```
lobby-compositor.service     → Hyprland Wayland compositor with ANGLE GPU acceleration
lobby-app.service           → Vue.js lobby display (port 8080, memory limited)
lobby-browser.service       → Chromium kiosk with crash detection wrapper
lobby-health-monitor.service → Network/browser/app monitoring (5-min checks)
```

### 🛡️ Reliability Design
- **Independent services** - Compositor, app, browser run separately to prevent cascade failures
- **Crash detection** - Browser wrapper prevents silent exits and 1.5+ hour blank screens  
- **Auto-recovery** - Failed services restart automatically with intelligent limits
- **Health monitoring** - Continuous checks with automatic component restart
- **Resource management** - Memory limits and security restrictions on app service
- **Fast boot** - Optimized dependencies for 8-15 second boot time

---

## System Management

### 🛠️ Management Commands

```bash
# Diagnostics
sudo lobby health                        # Comprehensive health check (20+ validations)
sudo lobby status                        # Real-time module status (✓ OK / ✗ FAILED)
sudo lobby logs                          # View recent system logs with filtering

# System Operations  
sudo lobby setup                         # Full system setup and configuration
sudo lobby validate                      # Validate all modules
sudo lobby sync && sudo lobby setup      # Update from git and refresh configuration

# Module-Specific Setup
sudo lobby setup compositor              # Configure Hyprland compositor
sudo lobby setup app                     # Configure Vue.js lobby display service
sudo lobby setup browser                 # Configure Chromium with crash detection
sudo lobby setup health-monitor          # Configure health monitoring
sudo lobby reset [module]                # Reset specific module to defaults
```

### System Features
- **Automated maintenance** - System updates at 2:00 AM with error recovery
- **Professional appearance** - No cursor display, direct boot to kiosk
- **AMD optimization** - Microcode updates and graphics drivers included
- **Network resilience** - Handles connectivity issues during operations
- **Enterprise logging** - Centralized logs with rotation and cleanup
- **VT switching** - Kiosk on VT2, TTY1 available for admin access

---

## Troubleshooting

For system issues, use these diagnostic commands:
```bash
sudo lobby status
sudo lobby health
sudo lobby logs
sudo journalctl -b | grep lobby
```
