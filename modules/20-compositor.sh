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

    # Install health monitor service
    cp "$config_dir/systemd/lobby-health-monitor.service" /etc/systemd/system/lobby-health-monitor.service
    log "Health monitor service installed from $config_dir/systemd/"

    # --- 7. Enable Services (let systemd start them when ready) ---
    log "Stopping Plymouth and switching to VT2 before enabling Hyprland compositor"
    systemctl stop plymouth-quit.service || true
    systemctl stop plymouth.service || true
    killall plymouthd || true
    chvt 2 || true

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