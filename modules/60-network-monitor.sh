#!/usr/bin/env bash
# Lobby Network Monitor Module (Mako notifications for offline status)

set -euo pipefail

# Module info
MODULE_NAME="Lobby Network Monitor Setup (Mako)"
MODULE_VERSION="1.0"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
USER="${LOBBY_USER:-lobby}"
HOME_DIR="${LOBBY_HOME:-/home/$USER}"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODULE_NAME] $1" | tee -a "${LOBBY_LOG:-/var/log/lobby-setup.log}"
}

# Main setup function
setup_network_monitor() {
    log "Setting up network monitoring with mako notifications"

    # Stop related services for clean setup
    log "Stopping network monitor services"
    systemctl stop lobby-network-monitor.service 2>/dev/null || true

    # --- 1. Install Required Packages ---
    log "Installing mako notification daemon and dependencies"
    pacman -S --noconfirm --needed mako jq || {
        log "ERROR: Failed to install mako or jq"
        return 1
    }

    # --- 2. Create Mako Configuration ---
    log "Installing mako configuration"
    local mako_config_dir="$HOME_DIR/.config/mako"
    mkdir -p "$mako_config_dir"

    local config_dir="$SCRIPT_DIR/../config"
    cp "$config_dir/mako/config" "$mako_config_dir/config"

    chown -R "$USER:$USER" "$HOME_DIR/.config"
    log "Mako configuration installed at $mako_config_dir/config"

    # --- 3. Install Network Monitoring Script ---
    log "Installing network monitoring script"
    cp "$config_dir/scripts/network-monitor.sh" /usr/local/bin/network-monitor.sh
    chmod +x /usr/local/bin/network-monitor.sh
    log "Network monitoring script installed at /usr/local/bin/network-monitor.sh"

    # --- 4. Create Systemd Services ---
    log "Installing network monitor systemd services"
    cp "$config_dir/systemd/lobby-network-monitor.service" /etc/systemd/system/lobby-network-monitor.service
    log "Network monitor service installed"

    # --- 5. Enable Services ---
    log "Enabling network monitor services"
    systemctl daemon-reload
    systemctl enable lobby-network-monitor.service

    log "Network monitor setup completed successfully"
}

# Reset function
reset_network_monitor() {
    log "Resetting network monitor configuration"

    # Stop and disable services
    systemctl stop lobby-network-monitor.service || true
    systemctl disable lobby-network-monitor.service || true

    # Remove service files
    rm -f /etc/systemd/system/lobby-network-monitor.service
    rm -f /usr/local/bin/network-monitor.sh

    # Clean up mako config
    rm -rf "$HOME_DIR/.config/mako"

    systemctl daemon-reload
    log "Network monitor reset completed"
}

# Validation function
validate_network_monitor() {
    local errors=0

    # Check if service file exists
    if [[ ! -f /etc/systemd/system/lobby-network-monitor.service ]]; then
        log "ERROR: Network monitor service not found"
        ((errors++))
    fi

    # Check if mako config exists
    if [[ ! -f "$HOME_DIR/.config/mako/config" ]]; then
        log "ERROR: Mako config not found"
        ((errors++))
    fi

    # Check if script exists
    if [[ ! -f /usr/local/bin/network-monitor.sh ]]; then
        log "ERROR: Network monitor script not found"
        ((errors++))
    fi

    # Check if mako is installed
    if ! command -v mako >/dev/null; then
        log "ERROR: Mako not installed"
        ((errors++))
    fi

    if [[ $errors -eq 0 ]]; then
        log "Network monitor validation passed"
        return 0
    else
        log "Network monitor validation failed with $errors errors"
        return 1
    fi
}

# Command line interface
case "${1:-setup}" in
    "setup")
        setup_network_monitor
        ;;
    "reset")
        reset_network_monitor
        ;;
    "validate")
        validate_network_monitor
        ;;
    *)
        echo "Usage: $0 {setup|reset|validate}"
        exit 1
        ;;
esac