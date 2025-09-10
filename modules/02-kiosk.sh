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
# --- Hyprland Kiosk Config ---

# Monitor setup
monitor=,preferred,auto,1

# Autostart Chromium in kiosk mode on launch
exec-once = chromium --enable-features=UseOzonePlatform --ozone-platform=wayland --no-sandbox --kiosk http://localhost:8080

# Make the Chromium window fullscreen
windowrulev2 = fullscreen,class:^(chromium)$

# General settings - one per line
general {
    gaps_in = 0
    gaps_out = 0
    border_size = 0
    layout = dwindle
}

# Decoration settings - disable rounded corners and shadows for a clean kiosk look
decoration {
    rounding = 0
    drop_shadow = false
}

# Miscellaneous settings
misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
}

# Input is implicitly disabled by not defining any input devices.
# We only define the cursor behavior.
cursor {
    inactive_timeout = 1
}
EOF
    chown -R "$USER:$USER" "$HOME_DIR/.config"

    # --- 5. Create Systemd Services ---
    log "Creating lobby-display systemd service"
    cat > /etc/systemd/system/lobby-display.service <<'EOF'
[Unit]
Description=Lobby Display Vue.js App
After=network-online.target
Wants=network-online.target

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
After=lobby-display.service seatd.service
Requires=lobby-display.service
Wants=seatd.service

[Service]
User=lobby
Group=seat
# Open a full PAM session to get a proper graphical environment
PAMName=login
# Explicitly set wlroots environment variables for AMD GPU
Environment="WLR_RENDERER=vulkan"
Environment="WLR_DRM_DEVICE=/dev/dri/card0"
# Wait for the display server to be ready before starting
ExecStartPre=/bin/bash -c 'while ! curl -s http://localhost:8080 >/dev/null; do sleep 1; done'
# Launch Hyprland
ExecStart=/usr/bin/Hyprland
Restart=always
RestartSec=5
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