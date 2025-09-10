#!/usr/bin/env bash
# Lobby Kiosk Configuration Module

set -euo pipefail

# Module info
MODULE_NAME="Lobby Kiosk Setup"
MODULE_VERSION="1.0"

# Get script directory - handle both direct execution and symlink scenarios
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# For symlinked lobby command, find the real script location
if [[ -L "/usr/local/bin/lobby" ]]; then
    REAL_LOBBY_SCRIPT="$(readlink -f /usr/local/bin/lobby)"
    REAL_SCRIPT_DIR="$(dirname "$REAL_LOBBY_SCRIPT")"
    CONFIG_DIR="$REAL_SCRIPT_DIR/configs"
else
    CONFIG_DIR="$SCRIPT_DIR/../configs"
fi

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

    # Install required packages (skip in chroot - already installed by arch-install.sh)
    if [[ -z "${CHROOT_INSTALL:-}" ]]; then
        log "Installing Wayland, Chromium, and font packages"
        pacman -S --noconfirm cage seatd chromium nodejs npm git xorg-xwayland \
            ttf-cascadia-code-nerd inter-font cairo freetype2 dbus
    else
        log "Skipping package installation (packages already installed by arch-install.sh)"
    fi

    # Configure fonts for better rendering
    log "Configuring font rendering"
    cat > /etc/fonts/local.conf <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- Enable antialiasing -->
  <match target="font">
    <edit mode="assign" name="antialias">
      <bool>true</bool>
    </edit>
  </match>

  <!-- Enable hinting -->
  <match target="font">
    <edit mode="assign" name="hinting">
      <bool>true</bool>
    </edit>
  </match>

  <!-- Use hintslight for better rendering -->
  <match target="font">
    <edit mode="assign" name="hintstyle">
      <const>hintslight</const>
    </edit>
  </match>

  <!-- Enable subpixel rendering for LCD screens -->
  <match target="font">
    <edit mode="assign" name="rgba">
      <const>rgb</const>
    </edit>
  </match>

  <!-- Use lcdfilter for subpixel rendering -->
  <match target="font">
    <edit mode="assign" name="lcdfilter">
      <const>lcddefault</const>
    </edit>
  </match>

  <!-- Font preferences -->
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Inter</family>
      <family>system-ui</family>
    </prefer>
  </alias>

  <alias>
    <family>serif</family>
    <prefer>
      <family>Inter</family>
      <family>system-ui</family>
    </prefer>
  </alias>

  <alias>
    <family>monospace</family>
    <prefer>
      <family>CaskaydiaCove Nerd Font Mono</family>
    </prefer>
  </alias>
</fontconfig>
EOF

    # Rebuild font cache
    log "Rebuilding font cache"
    fc-cache -fv

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

    # Install dependencies and build with retry logic
    log "Installing lobby-display dependencies"
    cd "$LOBBY_DISPLAY_DIR"

    # Retry npm install up to 3 times
    local npm_install_attempts=0
    while [ $npm_install_attempts -lt 3 ]; do
        log "Attempting npm install (attempt $((npm_install_attempts + 1))/3)"
        if sudo -u "$USER" npm install; then
            log "npm install successful"
            break
        else
            npm_install_attempts=$((npm_install_attempts + 1))
            if [ $npm_install_attempts -lt 3 ]; then
                log "npm install failed, retrying in 10 seconds..."
                sleep 10
                # Clean node_modules and package-lock.json for clean retry
                sudo -u "$USER" rm -rf node_modules package-lock.json
            else
                log "ERROR: npm install failed after 3 attempts"
                return 1
            fi
        fi
    done

    # Build the application
    log "Building lobby-display application"
    if ! sudo -u "$USER" npm run build; then
        log "ERROR: npm run build failed"
        return 1
    fi

    log "lobby-display build completed successfully"

    # Configure auto-login for lobby user (Arch Linux way)
    log "Configuring auto-login for lobby user"
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin $USER %I \$TERM
EOF

    # Create user systemd directory
    mkdir -p "$HOME_DIR/.config/systemd/user"
    
    # Create lobby-display user service
    log "Creating lobby-display user service"
    cat > "$HOME_DIR/.config/systemd/user/lobby-display.service" <<EOF
[Unit]
Description=Lobby Display Vue.js App
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$LOBBY_DISPLAY_DIR
ExecStart=/usr/bin/npm run preview -- --port 8080 --host
Restart=on-failure
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=default.target
EOF

    # Enable seatd for Wayland session management
    log "Setting up seatd for Wayland"
    if [[ -z "${CHROOT_INSTALL:-}" ]]; then
        systemctl enable --now seatd.service
    else
        systemctl enable seatd.service 2>/dev/null || true
        log "Seatd service enabled (will start on boot)"
    fi
    usermod -a -G seat "$USER"

    # Create kiosk user service (Arch Linux way)
    log "Creating kiosk user service"
    cat > "$HOME_DIR/.config/systemd/user/lobby-kiosk.service" <<EOF
[Unit]
Description=Lobby Kiosk Compositor
After=lobby-display.service
Wants=lobby-display.service

[Service]
Type=simple
# Wait for display service to be ready
ExecStartPre=/bin/bash -c 'while ! curl -s http://localhost:8080 >/dev/null; do sleep 2; done'
# Start Cage compositor with Chromium
ExecStart=/usr/bin/cage -s -- /usr/bin/chromium \\
    --enable-features=UseOzonePlatform --ozone-platform=wayland \\
    --no-sandbox --disable-dev-shm-usage --kiosk \\
    --disable-infobars --disable-session-crashed-bubble \\
    --disable-features=TranslateUI --no-first-run \\
    --disable-notifications --disable-extensions \\
    --start-fullscreen --hide-cursor \\
    --disable-logging --disable-sync \\
    --disable-default-apps --disable-background-networking \\
    http://localhost:8080
Environment=WLR_NO_HARDWARE_CURSORS=1
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

    # Set correct ownership for user systemd files
    chown -R "$USER:$USER" "$HOME_DIR/.config"
    
    # Enable user services (the Arch way)
    log "Enabling user services"
    if [[ -z "${CHROOT_INSTALL:-}" ]]; then
        # Enable user services immediately
        sudo -u "$USER" systemctl --user daemon-reload
        sudo -u "$USER" systemctl --user enable lobby-display.service
        sudo -u "$USER" systemctl --user enable lobby-kiosk.service
        # Enable lingering so user services start without login
        loginctl enable-linger "$USER"
    else
        log "User services will be enabled on first boot"
    fi

    log "Lobby kiosk setup completed"
}

# Reset function
reset_kiosk() {
    log "Resetting kiosk configuration"

    # Stop and disable services
    systemctl stop lobby-kiosk.service || true
    systemctl stop lobby-display.service || true
    systemctl disable lobby-kiosk.service || true
    systemctl disable lobby-display.service || true

    # Remove service files
    rm -f /etc/systemd/system/lobby-kiosk.service
    rm -f /etc/systemd/system/lobby-display.service

    # Re-enable getty@tty1
    systemctl unmask getty@tty1.service || true
    systemctl enable getty@tty1.service || true

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

    # Check if user service files exist
    if [[ ! -f "$HOME_DIR/.config/systemd/user/lobby-kiosk.service" ]]; then
        log "ERROR: Lobby kiosk user service not found"
        ((errors++))
    fi

    if [[ ! -f "$HOME_DIR/.config/systemd/user/lobby-display.service" ]]; then
        log "ERROR: Lobby display user service not found"
        ((errors++))
    fi

    # Check if lobby-display directory exists
    if [[ ! -d "$LOBBY_DISPLAY_DIR" ]]; then
        log "ERROR: Lobby display directory not found"
        ((errors++))
    fi

    # Check if auto-login is configured
    if [[ ! -f /etc/systemd/system/getty@tty1.service.d/autologin.conf ]]; then
        log "ERROR: Auto-login not configured"
        ((errors++))
    fi

    # Check if user is in seat group
    if ! groups "$USER" | grep -q seat; then
        log "ERROR: User $USER not in seat group"
        ((errors++))
    fi

    # Check if lingering is enabled
    if [[ ! -f "/var/lib/systemd/linger/$USER" ]]; then
        log "WARNING: User lingering not enabled - services may not start"
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
