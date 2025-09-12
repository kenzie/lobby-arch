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
    cat > "$hypr_config_dir/hyprland.conf" <<EOF
# --- Minimal Hyprland Kiosk Config for Maximum Stability ---
monitor=,preferred,auto,1
# Chromium is managed by lobby-chromium.service instead of exec-once
# This provides better crash recovery and restart reliability

general {
    border_size = 0
    layout = dwindle
    gaps_in = 0
    gaps_out = 0
}

decoration {
    rounding = 0
    blur {
        enabled = false
    }
    shadow {
        enabled = false
    }
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
    animate_manual_resizes = false
    animate_mouse_windowdragging = false
    enable_swallow = false
    no_direct_scanout = true
    # Disable VRR and other advanced features for stability
    vrr = 0
}

animations {
    enabled = false
}

cursor {
    no_hardware_cursors = true
    inactive_timeout = 1
}

# Disable XWayland for kiosk mode (not needed for Chromium on Wayland)
xwayland {
    enabled = false
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
# Ensure we're on VT2 and disable TTY1 getty to prevent fallback
ExecStartPre=/bin/bash -c 'systemctl stop getty@tty1.service getty@tty2.service 2>/dev/null || true; chvt 2; sleep 1'
# Launch Hyprland with software rendering for better stability
ExecStart=/bin/bash -c 'export XDG_RUNTIME_DIR=/run/user/1000; export XDG_SESSION_TYPE=wayland; export XDG_CURRENT_DESKTOP=Hyprland; export WLR_RENDERER=pixman; export WLR_NO_HARDWARE_CURSORS=1; export WLR_DRM_DEVICE=/dev/dri/card0; export WLR_VT=2; exec /usr/bin/Hyprland'
# Restart only on failure, not on normal exit
Restart=on-failure
RestartSec=3
# Better logging
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=graphical.target
EOF

    log "Creating Chromium monitoring systemd service"
    cat > /etc/systemd/system/lobby-chromium.service <<'EOF'
[Unit]
Description=Lobby Chromium Browser
After=lobby-display.service lobby-kiosk.service seatd.service
Requires=lobby-display.service
Wants=lobby-kiosk.service seatd.service
StartLimitIntervalSec=0

[Service]
Type=simple
User=lobby
Group=seat
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_CURRENT_DESKTOP=Hyprland
Environment=WAYLAND_DISPLAY=wayland-1
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

# Wait for Hyprland and display to be ready
ExecStartPre=/bin/bash -c 'while ! curl -s http://localhost:8080 >/dev/null; do sleep 1; done'
ExecStartPre=/bin/bash -c 'while ! pgrep -f "Hyprland" >/dev/null; do sleep 1; done; sleep 3'

# Launch Chromium in kiosk mode
ExecStart=/usr/bin/chromium --no-sandbox --disable-dev-shm-usage --disable-gpu --disable-software-rasterizer --disable-background-timer-throttling --disable-backgrounding-occluded-windows --disable-renderer-backgrounding --disable-extensions --disable-plugins --disable-sync --disable-translate --no-first-run --no-default-browser-check --kiosk http://localhost:8080

# Aggressive restart policy for maximum uptime
Restart=always
RestartSec=5

# Better logging
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target
EOF

    # --- 6. Disable Getty Services to Prevent Fallback ---
    log "Disabling getty services to prevent TTY fallback during kiosk mode"
    systemctl mask getty@tty1.service getty@tty2.service || true
    systemctl mask autovt@tty1.service autovt@tty2.service || true
    
    # --- 7. Remove Old Monitoring References ---
    log "Cleaning up old monitoring services if they exist"
    systemctl stop lobby-monitor.service lobby-monitor.timer boot-health-monitor.service 2>/dev/null || true
    systemctl disable lobby-monitor.service lobby-monitor.timer boot-health-monitor.service 2>/dev/null || true
    rm -f /etc/systemd/system/lobby-monitor.service /etc/systemd/system/lobby-monitor.timer /etc/systemd/system/boot-health-monitor.service
    rm -f /usr/local/bin/lobby-monitor.sh
    
    # --- 8. Enable Services and Set Boot Target ---
    log "Enabling services and setting default boot target"
    systemctl daemon-reload
    systemctl enable lobby-display.service
    systemctl enable lobby-kiosk.service
    systemctl enable lobby-chromium.service
    systemctl set-default graphical.target

    # --- 7. Remove Old Auto-Login Config ---
    log "Removing old auto-login configuration if it exists"
    rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf
    systemctl set-default graphical.target
    systemctl daemon-reload
    
    # --- 9. Post-Install Validation ---
    log "Running post-install validation check"
    if [[ -x "$SCRIPT_DIR/../scripts/boot-validator.sh" ]]; then
        # Ensure boot validator log file exists with proper permissions
        local validator_log="/var/log/boot-validator.log"
        if [[ ! -f "$validator_log" ]]; then
            touch "$validator_log"
            chown "$LOBBY_USER:$LOBBY_USER" "$validator_log"
            chmod 664 "$validator_log"
        fi
        
        if "$SCRIPT_DIR/../scripts/boot-validator.sh" validate >/dev/null 2>&1; then
            log "✅ Post-install validation PASSED"
        else
            log "⚠️  Post-install validation detected potential issues - check logs"
        fi
    fi

    log "Lobby kiosk setup with Hyprland completed"
}

# Reset function
reset_kiosk() {
    log "Resetting kiosk configuration to a standard console state"

    # Stop and disable services
    systemctl stop lobby-kiosk.service || true
    systemctl stop lobby-display.service || true
    systemctl stop lobby-chromium.service || true
    systemctl stop lobby-monitor.service lobby-monitor.timer boot-health-monitor.service || true
    systemctl disable lobby-kiosk.service || true
    systemctl disable lobby-display.service || true
    systemctl disable lobby-chromium.service || true
    systemctl disable lobby-monitor.service lobby-monitor.timer boot-health-monitor.service || true

    # Remove service files
    rm -f /etc/systemd/system/lobby-kiosk.service
    rm -f /etc/systemd/system/lobby-display.service
    rm -f /etc/systemd/system/lobby-chromium.service
    rm -f /etc/systemd/system/lobby-monitor.service
    rm -f /etc/systemd/system/lobby-monitor.timer
    rm -f /etc/systemd/system/boot-health-monitor.service
    rm -f /usr/local/bin/lobby-monitor.sh
    
    # Re-enable getty services for normal operation
    systemctl unmask getty@tty1.service getty@tty2.service || true
    systemctl unmask autovt@tty1.service autovt@tty2.service || true
    systemctl enable getty@tty1.service || true

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
    if [[ ! -f /etc/systemd/system/lobby-chromium.service ]]; then
        log "ERROR: Lobby chromium service not found"
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