#!/usr/bin/env bash
# Lobby Health Monitor Module (Network + Browser monitoring with Mako notifications)

set -euo pipefail

# Module info
MODULE_NAME="Lobby Health Monitor Setup (Mako)"
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
setup_health_monitor() {
    log "Setting up health monitoring (network + browser) with mako notifications"

    # Stop related services for clean setup
    log "Stopping health monitor services"
    systemctl stop lobby-health-monitor.service 2>/dev/null || true
    systemctl stop lobby-network-monitor.service 2>/dev/null || true  # Legacy cleanup

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

    # --- 3. Install Health Monitoring Script ---
    log "Installing health monitoring script"
    cp "$config_dir/scripts/health-monitor.sh" /usr/local/bin/health-monitor.sh
    chmod +x /usr/local/bin/health-monitor.sh
    log "Health monitoring script installed at /usr/local/bin/health-monitor.sh"

    # --- 4. Create Systemd Services ---
    log "Installing health monitor systemd services"
    cp "$config_dir/systemd/lobby-health-monitor.service" /etc/systemd/system/lobby-health-monitor.service
    log "Health monitor service installed"

    # --- 5. Enable Services ---
    log "Enabling health monitor services"
    systemctl daemon-reload
    systemctl enable lobby-health-monitor.service

    log "Health monitor setup completed successfully"
}

# Reset function
reset_health_monitor() {
    log "Resetting health monitor configuration"

    # Stop and disable services
    systemctl stop lobby-health-monitor.service || true
    systemctl disable lobby-health-monitor.service || true
    systemctl stop lobby-network-monitor.service || true
    systemctl disable lobby-network-monitor.service || true  # Legacy cleanup

    # Remove service files
    rm -f /etc/systemd/system/lobby-health-monitor.service
    rm -f /etc/systemd/system/lobby-network-monitor.service  # Legacy cleanup
    rm -f /usr/local/bin/health-monitor.sh
    rm -f /usr/local/bin/network-monitor.sh  # Legacy cleanup

    # Clean up mako config
    rm -rf "$HOME_DIR/.config/mako"

    systemctl daemon-reload
    log "Health monitor reset completed"
}

# Validation function
validate_health_monitor() {
    local errors=0

    # Check if service file exists
    if [[ ! -f /etc/systemd/system/lobby-health-monitor.service ]]; then
        log "ERROR: Health monitor service not found"
        ((errors++))
    fi

    # Check if mako config exists
    if [[ ! -f "$HOME_DIR/.config/mako/config" ]]; then
        log "ERROR: Mako config not found"
        ((errors++))
    fi

    # Check if script exists
    if [[ ! -f /usr/local/bin/health-monitor.sh ]]; then
        log "ERROR: Health monitor script not found"
        ((errors++))
    fi

    # Check if mako is installed
    if ! command -v mako >/dev/null; then
        log "ERROR: Mako not installed"
        ((errors++))
    fi

    if [[ $errors -eq 0 ]]; then
        log "Health monitor validation passed"
        return 0
    else
        log "Health monitor validation failed with $errors errors"
        return 1
    fi
}

# Command line interface
case "${1:-setup}" in
    "setup")
        setup_health_monitor
        ;;
    "reset")
        reset_health_monitor
        ;;
    "validate")
        validate_health_monitor
        ;;
    *)
        echo "Usage: $0 {setup|reset|validate}"
        exit 1
        ;;
esac