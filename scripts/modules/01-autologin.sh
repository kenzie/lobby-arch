#!/usr/bin/env bash
# Auto-login Configuration Module

set -euo pipefail

# Module info
MODULE_NAME="Auto-login Setup"
MODULE_VERSION="1.0"

# Default values
USER="${LOBBY_USER:-lobby}"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODULE_NAME] $1" | tee -a "${LOBBY_LOG:-/var/log/lobby-setup.log}"
}

# Main setup function
setup_autologin() {
    log "Setting up auto-login for $USER"
    
    # Create systemd override directory
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    
    # Create override configuration
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM
EOF
    
    # Reload systemd to apply changes
    systemctl daemon-reexec
    
    log "Auto-login configuration completed"
}

# Reset function
reset_autologin() {
    log "Resetting auto-login configuration"
    
    # Remove override configuration
    rm -rf /etc/systemd/system/getty@tty1.service.d
    
    # Reload systemd
    systemctl daemon-reexec
    
    # Recreate configuration
    setup_autologin
    
    log "Auto-login configuration reset completed"
}

# Validation function
validate_autologin() {
    local errors=0
    
    # Check if override directory exists
    if [[ ! -d /etc/systemd/system/getty@tty1.service.d ]]; then
        log "ERROR: Getty override directory not found"
        ((errors++))
    fi
    
    # Check if override file exists
    if [[ ! -f /etc/systemd/system/getty@tty1.service.d/override.conf ]]; then
        log "ERROR: Getty override configuration not found"
        ((errors++))
    fi
    
    # Check if configuration contains correct user
    if [[ -f /etc/systemd/system/getty@tty1.service.d/override.conf ]]; then
        if ! grep -q "autologin $USER" /etc/systemd/system/getty@tty1.service.d/override.conf; then
            log "ERROR: Auto-login not configured for user $USER"
            ((errors++))
        fi
    fi
    
    if [[ $errors -eq 0 ]]; then
        log "Auto-login validation passed"
        return 0
    else
        log "Auto-login validation failed with $errors errors"
        return 1
    fi
}

# Command line interface
case "${1:-setup}" in
    "setup")
        setup_autologin
        ;;
    "reset")
        reset_autologin
        ;;
    "validate")
        validate_autologin
        ;;
    *)
        echo "Usage: $0 {setup|reset|validate}"
        exit 1
        ;;
esac