#!/usr/bin/env bash
# Plymouth Boot Splash Configuration Module

set -euo pipefail

# Module info
MODULE_NAME="Plymouth Setup"
MODULE_VERSION="1.0"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../configs"

# Default values
USER="${LOBBY_USER:-lobby}"
HOME_DIR="${LOBBY_HOME:-/home/$USER}"
THEME_DIR="/usr/share/plymouth/themes/route19"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODULE_NAME] $1" | tee -a "${LOBBY_LOG:-/var/log/lobby-setup.log}"
}

# Main setup function
setup_plymouth() {
    log "Setting up Plymouth splash theme"
    
    # Create theme directory
    mkdir -p "$THEME_DIR"
    
    # Copy and process Plymouth theme files
    sed "s|{{THEME_DIR}}|$THEME_DIR|g" "$CONFIG_DIR/plymouth/route19.plymouth" > "$THEME_DIR/route19.plymouth"
    cp "$CONFIG_DIR/plymouth/route19.script" "$THEME_DIR/route19.script"
    
    # Copy logo to user's Hyprland config directory for wallpaper
    if [ -f /root/assets/route19-logo.png ]; then
        cp /root/assets/route19-logo.png "$HOME_DIR/.config/hypr/route19-centered.png"
        chown "$USER:$USER" "$HOME_DIR/.config/hypr/route19-centered.png"
        log "Route 19 logo copied for Hyprland wallpaper"
    else
        log "WARNING: Logo asset not found at /root/assets/route19-logo.png"
    fi
    
    # Copy logo for Plymouth theme
    if [ -f /root/assets/route19-logo.png ]; then
        cp /root/assets/route19-logo.png "$THEME_DIR/logo.png"
        log "Plymouth logo copied from assets"
    else
        log "WARNING: Logo asset not found, creating fallback"
        echo "Route 19" > "$THEME_DIR/logo.png"
    fi
    
    # Set Plymouth theme
    plymouth-set-default-theme -R route19 2>/dev/null || {
        log "WARNING: Failed to set Plymouth theme (may not be in chroot environment)"
    }
    
    log "Plymouth theme configuration completed"
}

# Reset function
reset_plymouth() {
    log "Resetting Plymouth configuration"
    
    # Remove theme directory
    rm -rf "$THEME_DIR"
    
    # Remove wallpaper from user directory
    rm -f "$HOME_DIR/.config/hypr/route19-centered.png"
    
    # Reset to default theme
    plymouth-set-default-theme -R text 2>/dev/null || true
    
    # Recreate configuration
    setup_plymouth
    
    log "Plymouth configuration reset completed"
}

# Validation function
validate_plymouth() {
    local errors=0
    
    # Check if theme directory exists
    if [[ ! -d "$THEME_DIR" ]]; then
        log "ERROR: Plymouth theme directory not found"
        ((errors++))
    fi
    
    # Check if theme files exist
    if [[ ! -f "$THEME_DIR/route19.plymouth" ]]; then
        log "ERROR: Plymouth theme file not found"
        ((errors++))
    fi
    
    if [[ ! -f "$THEME_DIR/route19.script" ]]; then
        log "ERROR: Plymouth script file not found"
        ((errors++))
    fi
    
    if [[ ! -f "$THEME_DIR/logo.png" ]]; then
        log "ERROR: Plymouth logo not found"
        ((errors++))
    fi
    
    # Check if wallpaper exists
    if [[ ! -f "$HOME_DIR/.config/hypr/route19-centered.png" ]]; then
        log "WARNING: Hyprland wallpaper not found"
    fi
    
    # Check current Plymouth theme
    local current_theme
    current_theme=$(plymouth-set-default-theme 2>/dev/null || echo "unknown")
    if [[ "$current_theme" != "route19" ]]; then
        log "WARNING: Plymouth theme not set to route19 (current: $current_theme)"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log "Plymouth validation passed"
        return 0
    else
        log "Plymouth validation failed with $errors errors"
        return 1
    fi
}

# Command line interface
case "${1:-setup}" in
    "setup")
        setup_plymouth
        ;;
    "reset")
        reset_plymouth
        ;;
    "validate")
        validate_plymouth
        ;;
    *)
        echo "Usage: $0 {setup|reset|validate}"
        exit 1
        ;;
esac