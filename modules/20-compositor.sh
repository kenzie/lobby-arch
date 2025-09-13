#!/usr/bin/env bash
# Lobby Compositor Module (Hyprland with ANGLE GPU Acceleration)

set -euo pipefail

# Module info
MODULE_NAME="Lobby Compositor Setup (Hyprland)"
MODULE_VERSION="2.0"

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
    log "Setting up Hyprland compositor with ANGLE GPU acceleration"

    # --- 1. Install Hyprland Package ---
    log "Installing Hyprland compositor"
    pacman -S --noconfirm --needed hyprland || {
        log "ERROR: Failed to install Hyprland"
        return 1
    }

    # --- 2. User Permissions ---
    log "Configuring user permissions for Hyprland"
    usermod -a -G seat,video "$USER"

    # --- 3. Create Hyprland Configuration ---
    log "Creating minimal Hyprland kiosk configuration"
    local hypr_config_dir="$HOME_DIR/.config/hypr"
    mkdir -p "$hypr_config_dir"
    
    cat > "$hypr_config_dir/hyprland.conf" <<'EOF'
# Hyprland Kiosk Configuration - Optimized for GPU Acceleration
# Designed for stable kiosk operation with ANGLE support

monitor=,preferred,auto,1

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
}

misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
    force_default_wallpaper = 0
    animate_manual_resizes = false
    animate_mouse_windowdragging = false
    enable_swallow = false
    vrr = 0
}

animations {
    enabled = false
}

cursor {
    no_hardware_cursors = true
    inactive_timeout = 8
}

# XWayland disabled - using native Wayland with ozone-platform
xwayland {
    enabled = false
}

# No key bindings defined for kiosk mode - prevents accidental interactions

# No auto-exec - browser launched by separate systemd service
# This ensures compositor and browser can restart independently
EOF
    
    chown -R "$USER:$USER" "$HOME_DIR/.config"
    log "Hyprland configuration created at $hypr_config_dir/hyprland.conf"

    # --- 4. Create Hyprland Systemd Service ---
    log "Creating Hyprland compositor systemd service"
    cat > /etc/systemd/system/lobby-compositor.service <<'EOF'
[Unit]
Description=Lobby Hyprland Compositor
After=systemd-user-sessions.service seatd.service
Wants=seatd.service

[Service]
Type=simple
User=lobby
Group=seat
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_CURRENT_DESKTOP=Hyprland
Environment=WLR_RENDERER=gles2
Environment=WLR_DRM_DEVICE=/dev/dri/card1
Environment=WLR_VT=2
Environment=WLR_NO_HARDWARE_CURSORS=1

# Ensure we're on VT2 and disable TTY1 getty
ExecStartPre=/bin/bash -c 'systemctl stop getty@tty1.service getty@tty2.service 2>/dev/null || true; chvt 2; sleep 1'

# Launch Hyprland compositor
ExecStart=/usr/bin/Hyprland

# Restart on failure only
Restart=on-failure
RestartSec=3
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
    log "Enabling Hyprland compositor service"
    systemctl daemon-reload
    systemctl enable lobby-compositor.service

    log "Hyprland compositor setup completed successfully"
}

# Reset function
reset_compositor() {
    log "Resetting Hyprland compositor configuration"

    # Stop and disable service
    systemctl stop lobby-compositor.service || true
    systemctl disable lobby-compositor.service || true

    # Remove service file
    rm -f /etc/systemd/system/lobby-compositor.service

    # Re-enable getty services
    systemctl unmask getty@tty1.service getty@tty2.service || true
    systemctl enable getty@tty1.service || true

    # Clean up Hyprland config
    rm -rf "$HOME_DIR/.config/hypr"

    systemctl daemon-reload
    log "Hyprland compositor reset completed"
}

# Validation function
validate_compositor() {
    local errors=0

    # Check if service file exists
    if [[ ! -f /etc/systemd/system/lobby-compositor.service ]]; then
        log "ERROR: Compositor service not found"
        ((errors++))
    fi

    # Check if Hyprland config exists
    if [[ ! -f "$HOME_DIR/.config/hypr/hyprland.conf" ]]; then
        log "ERROR: Hyprland config not found"
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