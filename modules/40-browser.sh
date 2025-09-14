#!/usr/bin/env bash
# Lobby Browser Module (Chromium Kiosk)

set -euo pipefail

# Module info
MODULE_NAME="Lobby Browser Setup (Chromium)"
MODULE_VERSION="1.0"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
USER="${LOBBY_USER:-lobby}"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODULE_NAME] $1" | tee -a "${LOBBY_LOG:-/var/log/lobby-setup.log}"
}

# Main setup function
setup_browser() {
    log "Setting up Chromium browser service for kiosk mode"
    
    # Stop browser service for clean setup
    log "Stopping browser service"
    systemctl stop lobby-browser.service 2>/dev/null || true

    # --- 1. Install Chromium ---
    log "Installing Chromium browser"
    pacman -S --noconfirm --needed chromium || {
        log "ERROR: Failed to install Chromium"
        return 1
    }

    # --- 2. Create Chromium Systemd Service ---
    log "Installing Chromium browser systemd service"
    local config_dir="$SCRIPT_DIR/../config"
    cp "$config_dir/systemd/lobby-browser.service" /etc/systemd/system/lobby-browser.service
    log "Lobby browser service installed from $config_dir/systemd/lobby-browser.service"

    # --- 3. Enable Service ---
    log "Enabling Chromium browser service"
    systemctl daemon-reload
    systemctl enable lobby-browser.service

    log "Chromium browser setup completed successfully"
}

# Reset function
reset_browser() {
    log "Resetting Chromium browser configuration"

    # Stop and disable service
    systemctl stop lobby-browser.service || true
    systemctl disable lobby-browser.service || true

    # Remove service file
    rm -f /etc/systemd/system/lobby-browser.service

    systemctl daemon-reload
    log "Chromium browser reset completed"
}

# Validation function
validate_browser() {
    local errors=0

    # Check if service file exists
    if [[ ! -f /etc/systemd/system/lobby-browser.service ]]; then
        log "ERROR: Browser service not found"
        ((errors++))
    fi

    # Check if Chromium is installed
    if ! command -v chromium >/dev/null; then
        log "ERROR: Chromium not installed"
        ((errors++))
    fi

    if [[ $errors -eq 0 ]]; then
        log "Browser validation passed"
        return 0
    else
        log "Browser validation failed with $errors errors"
        return 1
    fi
}

# Command line interface
case "${1:-setup}" in
    "setup")
        setup_browser
        ;;
    "reset")
        reset_browser
        ;;
    "validate")
        validate_browser
        ;;
    *)
        echo "Usage: $0 {setup|reset|validate}"
        exit 1
        ;;
esac