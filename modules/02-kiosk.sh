#!/usr/bin/env bash
# Lobby Kiosk Configuration Module (Hyprland Edition)

set -euo pipefail

# Module info
MODULE_NAME="Lobby Kiosk Setup (Hyprland)"
MODULE_VERSION="2.0"

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
    log "Setting up lobby kiosk system with Hyprland"

    # --- 1. Install Packages ---
    log "Ensuring packages are installed"
    pacman -S --noconfirm --needed hyprland xorg-xwayland chromium nodejs npm git ttf-cascadia-code-nerd inter-font || {
        log "ERROR: Failed to install packages"
        return 1
    }

    
    # --- 2. User and Permissions ---
    log "Configuring user permissions"
    usermod -a -G seat,video "$USER"

    # --- 3. Clone and Build Vue App ---
    log "Cloning lobby-display repository"
    if [[ -d "$LOBBY_DISPLAY_DIR" ]]; then
        log "Lobby display directory exists, pulling latest"
        cd "$LOBBY_DISPLAY_DIR"
        git pull
    else
        git clone "$LOBBY_DISPLAY_URL" "$LOBBY_DISPLAY_DIR"
    fi
    chown -R "$USER:$USER" "$LOBBY_DISPLAY_DIR"

    log "Installing lobby-display dependencies"
    cd "$LOBBY_DISPLAY_DIR"
    sudo -u "$USER" npm install || { log "ERROR: npm install failed"; return 1; }
    
    log "Building lobby-display application"
    sudo -u "$USER" npm run build || { log "ERROR: npm run build failed"; return 1; }
    log "lobby-display build completed successfully"

    # --- 4. Configure Hyprland ---
    log "Creating Hyprland kiosk configuration"
    local hypr_config_dir="$HOME_DIR/.config/hypr"
    mkdir -p "$hypr_config_dir"
    cat > "$hypr_config_dir/hyprland.conf" <<'EOF'
# --- Hyprland Kiosk Config (Fixed Syntax) ---
monitor=,preferred,auto,1
# Wait for Vue.js app to be ready, then launch Chromium in kiosk mode
exec-once = bash -c 'while ! curl -s http://localhost:8080 >/dev/null 2>&1; do sleep 1; done; sleep 2; export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"; chromium --no-sandbox --disable-dev-shm-usage --disable-gpu --disable-software-rasterizer --disable-background-timer-throttling --disable-backgrounding-occluded-windows --disable-renderer-backgrounding --disable-extensions --disable-plugins --disable-sync --disable-translate --no-first-run --no-default-browser-check --kiosk http://localhost:8080 2>/dev/null'
windowrulev2 = fullscreen,class:^(chromium)$

general {
    border_size = 0
    layout = dwindle
}

decoration {
    drop_shadow = false
    rounding = 0
}

input {
    kb_layout = us
    follow_mouse = 0
    sensitivity = 0
    # Disable all input for kiosk mode
}

misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
    force_default_wallpaper = 0
}

# Input devices managed through input section above for kiosk mode
# Note: device-specific blocks can cause crashes in some Hyprland versions
EOF
    chown -R "$USER:$USER" "$HOME_DIR/.config"

    # --- 5. Create Systemd Services ---
    log "Creating lobby-display systemd service"
    cat > /etc/systemd/system/lobby-display.service <<'EOF'
[Unit]
Description=Lobby Display Vue.js App
# Removed network-online.target dependency for faster boot
# Local Vue.js app doesn't require network connectivity to start

[Service]
Type=simple
User=lobby
WorkingDirectory=/opt/lobby-display
ExecStart=/usr/bin/npm run preview -- --port 8080 --host
Restart=on-failure
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF

    log "Creating Hyprland kiosk systemd service"
    cat > /etc/systemd/system/lobby-kiosk.service <<'EOF'
[Unit]
Description=Hyprland Kiosk
After=lobby-display.service seatd.service user@1000.service
Requires=lobby-display.service
Wants=seatd.service user@1000.service

[Service]
Type=simple
User=lobby
Group=seat
# Use systemd's user runtime directory (managed automatically)
PrivateUsers=false
# Wait for the display server to be ready before starting
ExecStartPre=/bin/bash -c 'while ! curl -s http://localhost:8080 >/dev/null; do sleep 1; done'
# Launch Hyprland with proper environment (XDG_RUNTIME_DIR set by systemd)
ExecStart=/bin/bash -c 'export XDG_RUNTIME_DIR=/run/user/1000; export XDG_SESSION_TYPE=wayland; export XDG_CURRENT_DESKTOP=Hyprland; export WLR_RENDERER=vulkan; export WLR_DRM_DEVICE=/dev/dri/card0; export WLR_NO_HARDWARE_CURSORS=1; exec /usr/bin/Hyprland 2>/dev/null'
Restart=always
RestartSec=2
# Better logging
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=graphical.target
EOF

    # --- 6. Enable Services and Set Boot Target ---
    log "Enabling services and setting default boot target"
    systemctl enable lobby-display.service
    systemctl enable lobby-kiosk.service
    systemctl set-default graphical.target

    # --- 7. Remove Old Auto-Login Config ---
    log "Removing old auto-login configuration if it exists"
    rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf
    systemctl set-default graphical.target
    systemctl daemon-reload

    log "Lobby kiosk setup with Hyprland completed"
}

# Reset function
reset_kiosk() {
    log "Resetting kiosk configuration to a standard console state"

    # Stop and disable services
    systemctl stop lobby-kiosk.service || true
    systemctl stop lobby-display.service || true
    systemctl disable lobby-kiosk.service || true
    systemctl disable lobby-display.service || true

    # Remove service files
    rm -f /etc/systemd/system/lobby-kiosk.service
    rm -f /etc/systemd/system/lobby-display.service

    # Set boot target back to default
    systemctl set-default multi-user.target

    # Clean up Hyprland config
    rm -rf "$HOME_DIR/.config/hypr"

    # Clean up lobby-display directory
    rm -rf "$LOBBY_DISPLAY_DIR"

    systemctl daemon-reload

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

    # Check if Hyprland config exists
    if [[ ! -f "$HOME_DIR/.config/hypr/hyprland.conf" ]]; then
        log "ERROR: Hyprland config not found"
        ((errors++))
    fi

    # Check if user is in correct groups
    if ! groups "$USER" | grep -q seat; then log "ERROR: User $USER not in seat group"; ((errors++)); fi
    if ! groups "$USER" | grep -q video; then log "ERROR: User $USER not in video group"; ((errors++)); fi

    # Check if default target is graphical
    if ! systemctl get-default | grep -q "graphical.target"; then
        log "WARNING: Default target is not graphical.target"
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