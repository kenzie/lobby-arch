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
    
    # Stop related services for clean setup
    log "Stopping compositor-related services"
    systemctl stop lobby-browser.service 2>/dev/null || true
    systemctl stop lobby-compositor.service 2>/dev/null || true
    systemctl stop lobby-health-monitor.service 2>/dev/null || true

    # --- 1. Install Hyprland Package and Dependencies ---
    log "Installing Hyprland compositor and seatd"
    pacman -S --noconfirm --needed hyprland seatd || {
        log "ERROR: Failed to install Hyprland or seatd"
        return 1
    }

    # --- 2. User Permissions ---
    log "Configuring user permissions for Hyprland"
    usermod -a -G seat,video "$USER"

    # --- 3. Create Hyprland Configuration ---
    log "Installing Hyprland kiosk configuration"
    local hypr_config_dir="$HOME_DIR/.config/hypr"
    mkdir -p "$hypr_config_dir"
    
    local config_dir="$SCRIPT_DIR/../config"
    cp "$config_dir/hyprland/hyprland.conf" "$hypr_config_dir/hyprland.conf"
    
    chown -R "$USER:$USER" "$HOME_DIR/.config"
    log "Hyprland configuration created at $hypr_config_dir/hyprland.conf"

    # --- 4. Create Hyprland Systemd Service ---
    log "Installing Hyprland compositor systemd service"
    local config_dir="$SCRIPT_DIR/../config"
    cp "$config_dir/systemd/lobby-compositor.service" /etc/systemd/system/lobby-compositor.service
    log "Lobby compositor service installed from $config_dir/systemd/lobby-compositor.service"

    # --- 5. Disable Getty Services ---
    log "Disabling getty services to prevent TTY fallback"
    systemctl mask getty@tty1.service getty@tty2.service || true
    systemctl mask autovt@tty1.service autovt@tty2.service || true

    # --- 6. Create Health Monitor ---
    log "Installing kiosk health monitoring system"
    cp "$config_dir/scripts/lobby-health-monitor.sh" /usr/local/bin/lobby-health-monitor.sh
    chmod +x /usr/local/bin/lobby-health-monitor.sh
    log "Health monitor script installed from $config_dir/scripts/lobby-health-monitor.sh"
#!/bin/bash
# Lobby Health Monitor - Detects and recovers from kiosk failures

HEALTH_LOG="/var/log/lobby-health.log"
MAX_FAILURES=3
FAILURE_COUNT=0

log_health() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [HEALTH] $1" | tee -a "$HEALTH_LOG"
}

check_kiosk_health() {
    # Check if all critical services are running
    if ! systemctl is-active lobby-compositor.service >/dev/null; then
        log_health "CRITICAL: Compositor service is not running"
        return 1
    fi

    if ! systemctl is-active lobby-app.service >/dev/null; then
        log_health "CRITICAL: App service is not running"
        return 1
    fi

    if ! systemctl is-active lobby-browser.service >/dev/null; then
        log_health "CRITICAL: Browser service is not running"
        return 1
    fi

    # Check if Wayland display is available
    if [ ! -S /run/user/1000/wayland-1 ]; then
        log_health "CRITICAL: Wayland display socket missing"
        return 1
    fi

    # Check if browser can connect to app
    if ! curl -s --max-time 5 http://localhost:8080 >/dev/null; then
        log_health "CRITICAL: App not responding on localhost:8080"
        return 1
    fi

    # Check if browser has GUI processes running
    if ! pgrep -f "chromium.*kiosk" >/dev/null; then
        log_health "CRITICAL: Browser kiosk process not found"
        return 1
    fi

    log_health "OK: All kiosk components healthy"
    return 0
}

recover_kiosk() {
    log_health "RECOVERY: Attempting kiosk recovery (failure $FAILURE_COUNT/$MAX_FAILURES)"

    # Restart services in order
    systemctl restart lobby-compositor.service
    sleep 5
    systemctl restart lobby-app.service
    sleep 3
    systemctl restart lobby-browser.service

    log_health "RECOVERY: Services restarted, waiting for stabilization"
    sleep 15
}

# Main health check loop
while true; do
    if check_kiosk_health; then
        FAILURE_COUNT=0
        sleep 30
    else
        ((FAILURE_COUNT++))

        if [ $FAILURE_COUNT -le $MAX_FAILURES ]; then
            recover_kiosk
            sleep 30
        else
            log_health "FATAL: Max failures reached ($MAX_FAILURES), stopping recovery attempts"
            systemctl reboot
            exit 1
        fi
    fi
done
EOF

    chmod +x /usr/local/bin/lobby-health-monitor.sh

    # Create health monitor service
    cat > /etc/systemd/system/lobby-health-monitor.service <<'EOF'
[Unit]
Description=Lobby Kiosk Health Monitor
After=lobby-compositor.service lobby-app.service lobby-browser.service
Wants=lobby-compositor.service lobby-app.service lobby-browser.service

[Service]
Type=simple
ExecStart=/usr/local/bin/lobby-health-monitor.sh
Restart=always
RestartSec=10
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target
EOF

    # --- 7. Enable Services (let systemd start them when ready) ---
    log "Enabling Hyprland compositor and health monitor services"
    systemctl daemon-reload
    
    # Enable seatd first (dependency)
    systemctl enable seatd.service
    
    # Enable compositor services
    systemctl enable lobby-compositor.service
    systemctl enable lobby-health-monitor.service

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