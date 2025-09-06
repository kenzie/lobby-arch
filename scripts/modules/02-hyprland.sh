#!/usr/bin/env bash
# Hyprland Configuration Module

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
    
    # Process and install Hyprland config
    sed "s/{{USER}}/$USER/g" "$CONFIG_DIR/hyprland.conf" > "$HOME_DIR/.config/hypr/hyprland.conf"
    
    # Process and install wallpaper script
    sed "s|{{HOME_DIR}}|$HOME_DIR|g" "$CONFIG_DIR/start-wallpaper.sh" > "$HOME_DIR/.config/hypr/start-wallpaper.sh"
    chmod +x "$HOME_DIR/.config/hypr/start-wallpaper.sh"
    
    # Create systemd service for Hyprland
    cat > "$HOME_DIR/.config/systemd/user/hyprland.service" <<EOF
[Unit]
Description=Hyprland Session
After=graphical.target

[Service]
ExecStart=/usr/bin/Hyprland
Restart=no
Environment=DISPLAY=:0

[Install]
WantedBy=default.target
EOF
    
    # Set ownership
    chown -R "$USER:$USER" "$HOME_DIR/.config"
    
    # Enable linger for user services
    loginctl enable-linger "$USER" 2>/dev/null || true
    
    log "Hyprland configuration completed"
}

# Reset function
reset_hyprland() {
    log "Resetting Hyprland configuration"
    
    # Stop user services
    systemctl --user --machine="$USER@" stop hyprland.service 2>/dev/null || true
    systemctl --user --machine="$USER@" disable hyprland.service 2>/dev/null || true
    
    # Remove configs
    rm -rf "$HOME_DIR/.config/hypr"
    rm -f "$HOME_DIR/.config/systemd/user/hyprland.service"
    
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