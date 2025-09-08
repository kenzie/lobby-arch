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
    log "Installing Wayland and Chromium packages"
    pacman -S --noconfirm cage seatd chromium nodejs npm git
    
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
ExecStart=/usr/bin/npm run preview -- --port 8080 --host
Restart=on-failure
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable seatd for Wayland session management
    log "Setting up seatd for Wayland"
    systemctl enable --now seatd.service
    usermod -a -G seat "$USER"
    
    # Create Wayland kiosk service
    log "Creating Wayland kiosk systemd service"
    cat > /etc/systemd/system/lobby-wayland.service <<EOF
[Unit]
Description=Lobby Wayland Kiosk Compositor
After=graphical.target seatd.service lobby-display.service
Requires=seatd.service lobby-display.service
BindsTo=lobby-display.service

[Service]
Type=simple
User=$USER
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=WLR_TTY=/dev/tty1
ExecStartPre=/usr/bin/mkdir -p /run/user/1000
ExecStartPre=/usr/bin/chown $USER:$USER /run/user/1000
ExecStartPre=/usr/bin/sleep 3
ExecStartPre=/bin/bash -c 'while ! curl -s http://localhost:8080 >/dev/null; do sleep 2; done'
ExecStart=/usr/bin/cage -d -- /usr/bin/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland --no-sandbox --disable-dev-shm-usage --kiosk --disable-infobars --disable-session-crashed-bubble --disable-features=TranslateUI --no-first-run --disable-notifications --disable-extensions --enable-gpu-rasterization --enable-oop-rasterization --enable-hardware-overlays --force-device-scale-factor=1.0 --start-fullscreen http://localhost:8080
Restart=on-failure
RestartSec=10

[Install]
WantedBy=graphical.target
EOF
    
    # Enable services
    log "Enabling kiosk services"
    systemctl daemon-reload
    systemctl enable lobby-display.service
    systemctl enable lobby-wayland.service
    
    log "Lobby kiosk setup completed"
}

# Reset function
reset_kiosk() {
    log "Resetting kiosk configuration"
    
    # Stop and disable services
    systemctl stop lobby-wayland.service || true
    systemctl stop lobby-display.service || true
    systemctl disable lobby-wayland.service || true
    systemctl disable lobby-display.service || true
    
    # Remove service files
    rm -f /etc/systemd/system/lobby-wayland.service
    rm -f /etc/systemd/system/lobby-display.service
    
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