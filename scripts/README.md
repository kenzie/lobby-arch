# Lobby System Scripts

This directory contains the modular installation and management system for lobby screens.

## Structure

```
scripts/
├── lobby.sh              # Main management script
├── post-install.sh       # Initial setup orchestrator
├── modules/              # Individual configuration modules
│   ├── 02-kiosk.sh
│   ├── 03-plymouth.sh
│   ├── 04-auto-updates.sh
│   ├── 05-monitoring.sh
│   ├── 06-scheduler.sh
│   └── 99-cleanup.sh
└── configs/              # Configuration templates
    ├── start-wallpaper.sh
    └── plymouth/
```

## Usage

### Initial Setup (automatically run during installation)
```bash
sudo ./post-install.sh
```

### Management Commands
```bash
# Full system management
sudo ./lobby.sh setup          # Complete setup
sudo ./lobby.sh reset          # Reset all configurations
sudo ./lobby.sh validate       # Validate installation
sudo ./lobby.sh status         # Show system status

# Individual module management  
sudo ./lobby.sh setup kiosk       # Setup only kiosk
sudo ./lobby.sh reset plymouth    # Reset Plymouth configuration
sudo ./lobby.sh update auto-updates  # Update automatic updates

# Information commands
./lobby.sh list            # List available modules
./lobby.sh logs            # Show recent logs
```

## Modules

- **kiosk**: Sets up auto-login + user systemd services for Cage Wayland kiosk compositor with Chromium
- **plymouth**: Configures animated Route 19 boot splash screen with loading dots  
- **auto-updates**: Sets up daily automatic system updates with git synchronization
- **monitoring**: Service health monitoring with automatic restart capabilities
- **scheduler**: Daily operation schedule (8:00 AM start, 11:59 PM stop)
- **cleanup**: Final cleanup, log rotation, and global command setup

Each module supports `setup`, `reset`, and `validate` operations.

## Environment Variables

- `LOBBY_USER`: Username (default: lobby)
- `LOBBY_HOME`: User home directory (default: /home/lobby)  
- `LOBBY_LOG`: Log file location (default: /var/log/lobby-setup.log)

## Benefits

- **Modular**: Update individual components without affecting others
- **Repeatable**: Reset and reconfigure any part of the system
- **Validated**: Each module can validate its configuration
- **Logged**: Comprehensive logging for troubleshooting
- **Extensible**: Easy to add new modules or modify existing ones