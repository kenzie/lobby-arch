#!/usr/bin/env bash
# Cleanup and Finalization Module

set -euo pipefail

# Module info
MODULE_NAME="Cleanup"
MODULE_VERSION="1.0"

# Default values
USER="${LOBBY_USER:-lobby}"
HOME_DIR="${LOBBY_HOME:-/home/$USER}"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODULE_NAME] $1" | tee -a "${LOBBY_LOG:-/var/log/lobby-setup.log}"
}

# Main setup function
setup_cleanup() {
    log "Running cleanup and finalization tasks"
    
    # Create first-login script to enable user services after login
    cat > "$HOME_DIR/.config/first-login.sh" <<'FIRSTLOGIN'
#!/bin/bash
# Enable and start Hyprland user service on first login only
if [ ! -f ~/.hyprland-enabled ]; then
    systemctl --user enable hyprland.service 2>/dev/null || true
    systemctl --user start hyprland.service 2>/dev/null || true
    touch ~/.hyprland-enabled
fi
FIRSTLOGIN

    chmod +x "$HOME_DIR/.config/first-login.sh"
    
    # Add to user's shell profile to run on first login
    cat >> "$HOME_DIR/.profile" <<'PROFILE'
# Run first-login setup if it exists
if [ -f ~/.config/first-login.sh ]; then
    ~/.config/first-login.sh
    rm -f ~/.config/first-login.sh
fi
PROFILE

    chown "$USER:$USER" "$HOME_DIR/.profile" "$HOME_DIR/.config/first-login.sh"
    
    log "First-login setup configured"
    
    # Clean up temporary assets if they exist
    if [[ -d /root/assets ]]; then
        log "Cleaning up temporary assets"
        rm -rf /root/assets
    fi
    
    log "Cleanup and finalization completed"
}

# Reset function
reset_cleanup() {
    log "Resetting cleanup configuration"
    
    # Remove first-login script
    rm -f "$HOME_DIR/.config/first-login.sh"
    
    # Remove profile additions (this is tricky, so we'll recreate a clean profile)
    if [[ -f "$HOME_DIR/.profile" ]]; then
        # Remove our additions from profile
        sed -i '/# Run first-login setup if it exists/,/fi/d' "$HOME_DIR/.profile"
    fi
    
    # Recreate cleanup
    setup_cleanup
    
    log "Cleanup configuration reset completed"
}

# Validation function
validate_cleanup() {
    local errors=0
    
    # Check if first-login script exists (it should exist until first login)
    # We can't reliably validate this since it gets removed after first run
    
    # Check if profile exists
    if [[ ! -f "$HOME_DIR/.profile" ]]; then
        log "ERROR: User profile not found"
        ((errors++))
    fi
    
    # Check profile ownership
    if [[ -f "$HOME_DIR/.profile" ]]; then
        local owner
        owner=$(stat -c '%U' "$HOME_DIR/.profile")
        if [[ "$owner" != "$USER" ]]; then
            log "ERROR: Profile ownership incorrect (expected: $USER, found: $owner)"
            ((errors++))
        fi
    fi
    
    if [[ $errors -eq 0 ]]; then
        log "Cleanup validation passed"
        return 0
    else
        log "Cleanup validation failed with $errors errors"
        return 1
    fi
}

# Command line interface
case "${1:-setup}" in
    "setup")
        setup_cleanup
        ;;
    "reset")
        reset_cleanup
        ;;
    "validate")
        validate_cleanup
        ;;
    *)
        echo "Usage: $0 {setup|reset|validate}"
        exit 1
        ;;
esac