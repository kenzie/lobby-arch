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

    # --- 1. Install Chromium ---
    log "Installing Chromium browser"
    pacman -S --noconfirm --needed chromium || {
        log "ERROR: Failed to install Chromium"
        return 1
    }

    # --- 2. Create Chromium Systemd Service ---
    log "Creating independent Chromium browser systemd service"
    cat > /etc/systemd/system/lobby-browser.service <<'EOF'
[Unit]
Description=Lobby Chromium Browser
After=lobby-compositor.service lobby-app.service seatd.service
Requires=lobby-app.service lobby-compositor.service
Wants=seatd.service

[Service]
Type=simple
User=lobby
Group=seat
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_CURRENT_DESKTOP=Hyprland
Environment=WAYLAND_DISPLAY=wayland-1
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

# Wait for dependencies to be ready
ExecStartPre=/bin/bash -c 'while ! curl -s http://localhost:8080 >/dev/null; do sleep 1; done'
ExecStartPre=/bin/bash -c 'while ! pgrep -f "Hyprland" >/dev/null; do sleep 1; done; sleep 3'
ExecStartPre=/bin/bash -c 'while [[ ! -S /run/user/1000/wayland-1 ]]; do sleep 1; done'

# Launch Chromium with Wayland native support (GPU disabled temporarily)
ExecStart=/usr/bin/chromium \
    --no-sandbox \
    --disable-dev-shm-usage \
    --disable-gpu \
    --ozone-platform=wayland \
    --enable-features=UseOzonePlatform \
    --disable-background-timer-throttling \
    --disable-backgrounding-occluded-windows \
    --disable-renderer-backgrounding \
    --disable-extensions \
    --disable-plugins \
    --disable-sync \
    --disable-translate \
    --no-first-run \
    --no-default-browser-check \
    --remote-debugging-port=9222 \
    --kiosk http://localhost:8080

# Aggressive restart policy for maximum uptime
Restart=always
RestartSec=5

# Kill entire process tree on stop
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=10

# Logging
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target
EOF

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