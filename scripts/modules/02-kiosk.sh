#!/usr/bin/env bash
# Lobby Kiosk Configuration Module

set -euo pipefail

# Module info
MODULE_NAME="Lobby Kiosk Setup"
MODULE_VERSION="1.0"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../configs"

# Default values
USER="${LOBBY_USER:-lobby}"
HOME_DIR="${LOBBY_HOME:-/home/$USER}"
LOBBY_DISPLAY_DIR="/opt/lobby-display"
LOBBY_DISPLAY_URL="https://github.com/kenzie/lobby-display.git"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODULE_NAME] $1" | tee -a "${LOBBY_LOG:-/var/log/lobby-setup.log}"
}

# Main setup function
setup_kiosk() {
    log "Setting up lobby kiosk system"
    
    # Install required packages
    log "Installing X11 and Chromium packages"
    pacman -S --noconfirm xorg-server xorg-xinit chromium nodejs npm git
    
    # Clone lobby-display repository
    log "Cloning lobby-display repository"
    if [[ -d "$LOBBY_DISPLAY_DIR" ]]; then
        log "Lobby display directory exists, pulling latest"
        cd "$LOBBY_DISPLAY_DIR"
        git pull
    else
        git clone "$LOBBY_DISPLAY_URL" "$LOBBY_DISPLAY_DIR"
        chown -R "$USER:$USER" "$LOBBY_DISPLAY_DIR"
    fi
    
    # Install dependencies and build
    log "Installing lobby-display dependencies"
    cd "$LOBBY_DISPLAY_DIR"
    sudo -u "$USER" npm install
    sudo -u "$USER" npm run build
    
    # Create systemd service for lobby display app
    log "Creating lobby-display systemd service"
    cat > /etc/systemd/system/lobby-display.service <<EOF
[Unit]
Description=Lobby Display Vue.js App
After=network.target
Requires=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$LOBBY_DISPLAY_DIR
ExecStart=/usr/bin/npm run dev -- --port 8080 --host
Restart=on-failure
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF
    
    # Create systemd service for Chromium kiosk
    log "Creating Chromium kiosk systemd service"
    cat > /etc/systemd/system/lobby-kiosk.service <<EOF
[Unit]
Description=Lobby Chromium Kiosk
After=lobby-display.service network.target
Requires=lobby-display.service
BindsTo=lobby-display.service

[Service]
Type=simple
User=$USER
Environment=DISPLAY=:0
ExecStartPre=/usr/bin/sleep 5
ExecStartPre=/bin/bash -c 'while ! curl -s http://localhost:8080 >/dev/null; do sleep 2; done'
ExecStart=/usr/bin/chromium --no-sandbox --disable-dev-shm-usage --kiosk --disable-infobars --disable-session-crashed-bubble --disable-features=TranslateUI --no-first-run --disable-notifications --disable-extensions http://localhost:8080
Restart=on-failure
RestartSec=10

[Install]
WantedBy=graphical.target
EOF
    
    # Create X server service
    log "Creating X server systemd service"
    cat > /etc/systemd/system/xserver.service <<EOF
[Unit]
Description=X Server for Lobby Kiosk
After=multi-user.target
Before=lobby-kiosk.service

[Service]
Type=simple
User=$USER
ExecStart=/usr/bin/X :0 vt1 -nolisten tcp
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical.target
EOF
    
    # Enable services
    log "Enabling kiosk services"
    systemctl daemon-reload
    systemctl enable xserver.service
    systemctl enable lobby-display.service
    systemctl enable lobby-kiosk.service
    
    log "Lobby kiosk setup completed"
}

# Reset function
reset_kiosk() {
    log "Resetting kiosk configuration"
    
    # Stop and disable services
    systemctl stop lobby-kiosk.service || true
    systemctl stop lobby-display.service || true
    systemctl stop xserver.service || true
    systemctl disable lobby-kiosk.service || true
    systemctl disable lobby-display.service || true
    systemctl disable xserver.service || true
    
    # Remove service files
    rm -f /etc/systemd/system/lobby-kiosk.service
    rm -f /etc/systemd/system/lobby-display.service
    rm -f /etc/systemd/system/xserver.service
    
    # Clean up lobby-display directory
    rm -rf "$LOBBY_DISPLAY_DIR"
    
    systemctl daemon-reload
    
    # Recreate
    setup_kiosk
    
    log "Kiosk configuration reset completed"
}

# Validation function
validate_kiosk() {
    local errors=0
    
    # Check if service files exist
    if [[ ! -f /etc/systemd/system/lobby-kiosk.service ]]; then
        log "ERROR: Lobby kiosk service not found"
        ((errors++))
    fi
    
    if [[ ! -f /etc/systemd/system/lobby-display.service ]]; then
        log "ERROR: Lobby display service not found"
        ((errors++))
    fi
    
    if [[ ! -f /etc/systemd/system/xserver.service ]]; then
        log "ERROR: X server service not found"
        ((errors++))
    fi
    
    # Check if lobby-display directory exists
    if [[ ! -d "$LOBBY_DISPLAY_DIR" ]]; then
        log "ERROR: Lobby display directory not found"
        ((errors++))
    fi
    
    # Check if services are enabled
    if ! systemctl is-enabled lobby-kiosk.service >/dev/null 2>&1; then
        log "ERROR: Lobby kiosk service not enabled"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log "Kiosk validation passed"
        return 0
    else
        log "Kiosk validation failed with $errors errors"
        return 1
    fi
}

# Command line interface
case "${1:-setup}" in
    "setup")
        setup_kiosk
        ;;
    "reset")
        reset_kiosk
        ;;
    "validate")
        validate_kiosk
        ;;
    *)
        echo "Usage: $0 {setup|reset|validate}"
        exit 1
        ;;
esac