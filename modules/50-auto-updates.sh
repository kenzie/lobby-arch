#!/usr/bin/env bash
# Automatic Updates Configuration Module

set -euo pipefail

# Module info
MODULE_NAME="Auto-updates Setup"
MODULE_VERSION="1.0"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODULE_NAME] $1" | tee -a "${LOBBY_LOG:-/var/log/lobby-setup.log}"
}

# Main setup function
setup_auto_updates() {
    log "Setting up automatic pacman updates"

    # Install required packages for auto-updates
    pacman -S --needed --noconfirm pacman-contrib
    log "Installed pacman-contrib for paccache functionality"

    # Copy the update script from config
    local config_dir="$SCRIPT_DIR/../config"
    cp "$config_dir/scripts/lobby-auto-update.sh" /usr/local/bin/lobby-auto-update.sh
    chmod +x /usr/local/bin/lobby-auto-update.sh
    log "Lobby auto-update script installed from $config_dir/scripts/lobby-auto-update.sh"
    
    # Install systemd service and timer for automatic updates
    local config_dir="$SCRIPT_DIR/../config"
    cp "$config_dir/systemd/lobby-auto-update.service" /etc/systemd/system/lobby-auto-update.service
    cp "$config_dir/systemd/lobby-auto-update.timer" /etc/systemd/system/lobby-auto-update.timer
    log "Auto-update systemd files installed from $config_dir/systemd/"

    # Install logrotate configuration (ensure directory exists)
    mkdir -p /etc/logrotate.d
    cp "$config_dir/logrotate/lobby-auto-update" /etc/logrotate.d/lobby-auto-update
    log "Auto-update logrotate config installed from $config_dir/logrotate/lobby-auto-update"

    # Enable the update timer (but don't start immediately - wait for scheduled time)
    systemctl daemon-reload
    systemctl enable lobby-auto-update.timer
    # Don't start timer during setup - it will start on next boot and run at scheduled 2 AM time
    
    log "Automatic lobby updates configured - runs daily at 2 AM with error recovery and log management"
}

# Reset function
reset_auto_updates() {
    log "Resetting automatic updates configuration"
    
    # Stop and disable timer and service
    systemctl stop lobby-auto-update.timer 2>/dev/null || true
    systemctl disable lobby-auto-update.timer 2>/dev/null || true
    systemctl stop lobby-auto-update.service 2>/dev/null || true
    systemctl disable lobby-auto-update.service 2>/dev/null || true
    
    # Remove files
    rm -f /usr/local/bin/lobby-auto-update.sh
    rm -f /etc/systemd/system/lobby-auto-update.service
    rm -f /etc/systemd/system/lobby-auto-update.timer
    rm -f /etc/logrotate.d/lobby-auto-update
    
    # Reload systemd
    systemctl daemon-reload
    
    # Recreate configuration
    setup_auto_updates
    
    log "Automatic updates configuration reset completed"
}

# Validation function
validate_auto_updates() {
    local errors=0
    
    # Check if script exists and is executable
    if [[ ! -f /usr/local/bin/lobby-auto-update.sh ]]; then
        log "ERROR: Update script not found"
        ((errors++))
    elif [[ ! -x /usr/local/bin/lobby-auto-update.sh ]]; then
        log "ERROR: Update script not executable"
        ((errors++))
    fi
    
    # Check systemd service
    if [[ ! -f /etc/systemd/system/lobby-auto-update.service ]]; then
        log "ERROR: Update service not found"
        ((errors++))
    fi
    
    # Check systemd timer
    if [[ ! -f /etc/systemd/system/lobby-auto-update.timer ]]; then
        log "ERROR: Update timer not found"
        ((errors++))
    fi
    
    # Check if timer is enabled and active
    if ! systemctl is-enabled lobby-auto-update.timer >/dev/null 2>&1; then
        log "ERROR: Update timer not enabled"
        ((errors++))
    fi
    
    if ! systemctl is-active lobby-auto-update.timer >/dev/null 2>&1; then
        log "ERROR: Update timer not active"
        ((errors++))
    fi
    
    # Check logrotate config
    if [[ ! -f /etc/logrotate.d/lobby-auto-update ]]; then
        log "ERROR: Logrotate configuration not found"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log "Auto-updates validation passed"
        return 0
    else
        log "Auto-updates validation failed with $errors errors"
        return 1
    fi
}

# Command line interface
case "${1:-setup}" in
    "setup")
        setup_auto_updates
        ;;
    "reset")
        reset_auto_updates
        ;;
    "validate")
        validate_auto_updates
        ;;
    *)
        echo "Usage: $0 {setup|reset|validate}"
        exit 1
        ;;
esac