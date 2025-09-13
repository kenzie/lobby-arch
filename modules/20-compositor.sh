#!/usr/bin/env bash
# Lobby Compositor Module (Sway - Production Stable)

set -euo pipefail

# Module info
MODULE_NAME="Lobby Compositor Setup (Sway)"
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
setup_compositor() {
    log "Setting up Sway compositor for production kiosk stability"

    # --- 1. Install Sway Package ---
    log "Installing Sway compositor"
    pacman -S --noconfirm --needed sway || {
        log "ERROR: Failed to install Sway"
        return 1
    }

    # --- 2. User Permissions ---
    log "Configuring user permissions for Sway"
    usermod -a -G seat,video "$USER"

    # --- 3. Create Sway Configuration ---
    log "Creating minimal Sway kiosk configuration"
    local sway_config_dir="$HOME_DIR/.config/sway"
    mkdir -p "$sway_config_dir"
    
    cat > "$sway_config_dir/config" <<'EOF'
# Sway Kiosk Configuration - Production Stable
# Optimized for single-application fullscreen display

# Output configuration
output * enable
output * {
    bg #0f172a solid_color
    scale 1
}

# Input configuration - minimal for kiosk
input * {
    xkb_layout us
    # Hide cursor after 8 seconds of inactivity
}

seat * hide_cursor 8000

# Disable all window decorations
default_border none
default_floating_border none
font pango:monospace 8
titlebar_border_thickness 0
titlebar_padding 0

# Disable gaps
gaps inner 0
gaps outer 0

# Window rules for kiosk mode
for_window [app_id="chromium-browser"] fullscreen enable
for_window [class="chromium"] fullscreen enable

# No key bindings defined for kiosk mode - prevents accidental interactions

# No auto-exec - browser launched by separate systemd service
# This ensures compositor and browser can restart independently
EOF
    
    chown -R "$USER:$USER" "$HOME_DIR/.config"
    log "Sway configuration created at $sway_config_dir/config"

    # --- 4. Create Sway Systemd Service ---
    log "Creating Sway compositor systemd service"
    cat > /etc/systemd/system/lobby-compositor.service <<'EOF'
[Unit]
Description=Lobby Sway Compositor
After=systemd-user-sessions.service seatd.service
Wants=seatd.service

[Service]
Type=simple
User=lobby
Group=seat
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_CURRENT_DESKTOP=sway
Environment=WLR_RENDERER=gles2
Environment=WLR_DRM_DEVICE=/dev/dri/card1
Environment=WLR_VT=2

# Ensure we're on VT2 and disable TTY1 getty
ExecStartPre=/bin/bash -c 'systemctl stop getty@tty1.service getty@tty2.service 2>/dev/null || true; chvt 2; sleep 1'

# Launch Sway compositor
ExecStart=/usr/bin/sway
# Ensure display output is enabled after startup with retries
ExecStartPost=/bin/bash -c 'sleep 5; export SWAYSOCK=/run/user/1000/sway-ipc.1000.$MAINPID.sock; swaymsg output HDMI-A-1 enable || true'

# Restart on failure only
Restart=on-failure
RestartSec=2
StartLimitIntervalSec=30
StartLimitBurst=3

# Logging
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target
EOF

    # --- 5. Disable Getty Services ---
    log "Disabling getty services to prevent TTY fallback"
    systemctl mask getty@tty1.service getty@tty2.service || true
    systemctl mask autovt@tty1.service autovt@tty2.service || true

    # --- 6. Enable Service ---
    log "Enabling Sway compositor service"
    systemctl daemon-reload
    systemctl enable lobby-compositor.service

    log "Sway compositor setup completed successfully"
}

# Reset function
reset_compositor() {
    log "Resetting Sway compositor configuration"

    # Stop and disable service
    systemctl stop lobby-compositor.service || true
    systemctl disable lobby-compositor.service || true

    # Remove service file
    rm -f /etc/systemd/system/lobby-compositor.service

    # Re-enable getty services
    systemctl unmask getty@tty1.service getty@tty2.service || true
    systemctl enable getty@tty1.service || true

    # Clean up Sway config
    rm -rf "$HOME_DIR/.config/sway"

    systemctl daemon-reload
    log "Sway compositor reset completed"
}

# Validation function
validate_compositor() {
    local errors=0

    # Check if service file exists
    if [[ ! -f /etc/systemd/system/lobby-compositor.service ]]; then
        log "ERROR: Compositor service not found"
        ((errors++))
    fi

    # Check if Sway config exists
    if [[ ! -f "$HOME_DIR/.config/sway/config" ]]; then
        log "ERROR: Sway config not found"
        ((errors++))
    fi

    # Check user permissions
    if ! groups "$USER" | grep -q seat; then log "ERROR: User $USER not in seat group"; ((errors++)); fi
    if ! groups "$USER" | grep -q video; then log "ERROR: User $USER not in video group"; ((errors++)); fi

    if [[ $errors -eq 0 ]]; then
        log "Compositor validation passed"
        return 0
    else
        log "Compositor validation failed with $errors errors"
        return 1
    fi
}

# Command line interface
case "${1:-setup}" in
    "setup")
        setup_compositor
        ;;
    "reset")
        reset_compositor
        ;;
    "validate")
        validate_compositor
        ;;
    *)
        echo "Usage: $0 {setup|reset|validate}"
        exit 1
        ;;
esac