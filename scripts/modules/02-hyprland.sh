#!/usr/bin/env bash
# Hyprland Configuration Module
# Test change for sync functionality

set -euo pipefail

# Module info
MODULE_NAME="Hyprland Setup"
MODULE_VERSION="1.0"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../configs"

# Default values
USER="${LOBBY_USER:-lobby}"
HOME_DIR="${LOBBY_HOME:-/home/$USER}"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODULE_NAME] $1" | tee -a "${LOBBY_LOG:-/var/log/lobby-setup.log}"
}

# Main setup function
setup_hyprland() {
    log "Setting up Hyprland configuration"
    
    # Create directories
    mkdir -p "$HOME_DIR/.config/hypr"
    mkdir -p "$HOME_DIR/.config/systemd/user"
    
    # Copy configuration files (no template substitution needed)
    cp "$CONFIG_DIR/hyprland.conf" "$HOME_DIR/.config/hypr/hyprland.conf"
    cp "$CONFIG_DIR/start-wallpaper.sh" "$HOME_DIR/.config/hypr/start-wallpaper.sh"
    chmod +x "$HOME_DIR/.config/hypr/start-wallpaper.sh"
    
    # Set ownership
    chown -R "$USER:$USER" "$HOME_DIR/.config"
    
    # Add auto-start logic to bash profile for tty1 kiosk mode
    cat >> "$HOME_DIR/.bash_profile" <<'EOF'

# Auto-start Hyprland on tty1 for kiosk mode
if [[ "$(tty)" == "/dev/tty1" ]]; then
    exec Hyprland
fi
EOF
    
    # Enable seatd service for Wayland session management
    log "Enabling seatd service"
    systemctl enable seatd 2>/dev/null || true
    systemctl start seatd 2>/dev/null || true
    
    # Add user to seat group for seatd access
    log "Adding user to seat group"
    usermod -a -G seat "$USER" 2>/dev/null || true
    
    # Enable linger for user services
    loginctl enable-linger "$USER" 2>/dev/null || true
    
    log "Hyprland configuration completed"
}

# Reset function
reset_hyprland() {
    log "Resetting Hyprland configuration"
    
    # Remove configs
    rm -rf "$HOME_DIR/.config/hypr"
    
    # Reset bash profile (remove Hyprland auto-start section)
    if [[ -f "$HOME_DIR/.bash_profile" ]]; then
        sed -i '/# Auto-start Hyprland on tty1 for kiosk mode/,/^fi$/d' "$HOME_DIR/.bash_profile"
    fi
    
    # Recreate and setup
    setup_hyprland
    
    log "Hyprland configuration reset completed"
}

# Validation function
validate_hyprland() {
    local errors=0
    
    # Check if config files exist
    if [[ ! -f "$HOME_DIR/.config/hypr/hyprland.conf" ]]; then
        log "ERROR: Hyprland config not found"
        ((errors++))
    fi
    
    if [[ ! -f "$HOME_DIR/.config/hypr/start-wallpaper.sh" ]]; then
        log "ERROR: Wallpaper script not found"
        ((errors++))
    fi
    
    if [[ ! -x "$HOME_DIR/.config/hypr/start-wallpaper.sh" ]]; then
        log "ERROR: Wallpaper script not executable"
        ((errors++))
    fi
    
    # Check if bash profile has auto-start logic
    if ! grep -q "Auto-start Hyprland on tty1 for kiosk mode" "$HOME_DIR/.bash_profile" 2>/dev/null; then
        log "ERROR: Hyprland auto-start not configured in bash profile"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log "Hyprland validation passed"
        return 0
    else
        log "Hyprland validation failed with $errors errors"
        return 1
    fi
}

# Command line interface
case "${1:-setup}" in
    "setup")
        setup_hyprland
        ;;
    "reset")
        reset_hyprland
        ;;
    "validate")
        validate_hyprland
        ;;
    *)
        echo "Usage: $0 {setup|reset|validate}"
        exit 1
        ;;
esac