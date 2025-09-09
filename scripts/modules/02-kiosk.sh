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
    log "Installing Wayland, Chromium, and font packages"
    pacman -S --noconfirm cage seatd chromium nodejs npm git xorg-xwayland \
        ttf-cascadia-code-nerd inter-font cairo freetype2

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

    # Create kiosk service - runs Cage directly without login
    log "Creating kiosk systemd service"
    cat > /etc/systemd/system/lobby-kiosk.service <<EOF
[Unit]
Description=Lobby Kiosk Compositor
After=multi-user.target lobby-display.service seatd.service
Requires=lobby-display.service seatd.service
BindsTo=lobby-display.service

[Service]
Type=simple
User=$USER
Group=seat
Environment=XDG_RUNTIME_DIR=/run/lobby-kiosk
ExecStartPre=/usr/bin/mkdir -p /run/lobby-kiosk
ExecStartPre=/usr/bin/chown $USER:$USER /run/lobby-kiosk
ExecStartPre=/usr/bin/sleep 3
ExecStartPre=/bin/bash -c 'while ! curl -s http://localhost:8080 >/dev/null; do sleep 2; done'
ExecStart=/usr/bin/cage -s -- /usr/bin/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland --no-sandbox --disable-dev-shm-usage --kiosk --disable-infobars --disable-session-crashed-bubble --disable-features=TranslateUI --no-first-run --disable-notifications --disable-extensions --enable-gpu-rasterization --enable-oop-rasterization --enable-hardware-overlays --force-device-scale-factor=1.0 --start-fullscreen --disable-background-timer-throttling --disable-renderer-backgrounding --disable-backgrounding-occluded-windows --memory-pressure-off --max_old_space_size=512 --aggressive-cache-discard --purge-memory-button --kiosk-printing --disable-pinch --overscroll-history-navigation=0 --disable-touch-editing --disable-touch-adjustment --hide-cursor http://localhost:8080
Restart=always
RestartSec=5
StartLimitBurst=10
StartLimitIntervalSec=60
RuntimeDirectory=lobby-kiosk
RuntimeDirectoryMode=0755

[Install]
WantedBy=multi-user.target
EOF

    # Disable getty on tty1 to prevent login prompt interference
    log "Disabling getty@tty1 service for clean kiosk boot"
    systemctl disable getty@tty1.service || true
    systemctl mask getty@tty1.service || true

    # Enable services
    log "Enabling kiosk services"
    systemctl daemon-reload
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

    # Check if service files exist
    if [[ ! -f /etc/systemd/system/lobby-kiosk.service ]]; then
        log "ERROR: Lobby kiosk service not found"
        ((errors++))
    fi

    if [[ ! -f /etc/systemd/system/lobby-display.service ]]; then
        log "ERROR: Lobby display service not found"
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

    if ! systemctl is-enabled lobby-display.service >/dev/null 2>&1; then
        log "ERROR: Lobby display service not enabled"
        ((errors++))
    fi

    # Check if getty@tty1 is masked (good for kiosk)
    if ! systemctl is-masked getty@tty1.service >/dev/null 2>&1; then
        log "WARNING: getty@tty1 service not masked - login prompt may interfere with kiosk"
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
