#!/usr/bin/env bash
# Cleanup and Finalization Module

set -euo pipefail

# Module info
MODULE_NAME="Cleanup"
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

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODULE_NAME] $1" | tee -a "${LOBBY_LOG:-/var/log/lobby-setup.log}"
}

# Main setup function
setup_cleanup() {
    log "Running cleanup and finalization tasks"

    # Create global lobby command symlink
    log "Creating global lobby command"
    ln -sf /root/scripts/lobby.sh /usr/local/bin/lobby
    
    # Remove any stale module copies in /usr/local/bin to avoid confusion
    log "Cleaning up stale module copies"
    rm -rf /usr/local/bin/modules /usr/local/bin/configs

    log "Global lobby command created at /usr/local/bin/lobby"

    # Configure log rotation
    log "Setting up log rotation"
    cat > /etc/logrotate.d/lobby <<'EOF'
/var/log/lobby-*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}

/var/log/post-install.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF

    # Configure systemd journal limits to prevent disk space issues
    log "Configuring systemd journal size limits"
    mkdir -p /etc/systemd/journald.conf.d
    cat > /etc/systemd/journald.conf.d/lobby.conf <<'EOF'
[Journal]
SystemMaxUse=100M
SystemMaxFileSize=10M
SystemMaxFiles=10
RuntimeMaxUse=50M
RuntimeMaxFileSize=5M
RuntimeMaxFiles=10
MaxRetentionSec=1week
EOF

    # Restart journald to apply new configuration
    systemctl restart systemd-journald

    # Clean up temporary assets if they exist
    if [[ -d /root/assets ]]; then
        log "Cleaning up temporary assets"
        rm -rf /root/assets
    fi

    # Install maintenance boot check service
    log "Installing maintenance boot check service"
    # Try both possible paths due to git repository structure differences
    if [[ -f "/root/scripts/configs/maintenance-boot-check.sh" ]]; then
        cp "/root/scripts/configs/maintenance-boot-check.sh" /usr/local/bin/maintenance-boot-check.sh
    elif [[ -f "/root/scripts/scripts/configs/maintenance-boot-check.sh" ]]; then
        cp "/root/scripts/scripts/configs/maintenance-boot-check.sh" /usr/local/bin/maintenance-boot-check.sh
        log "Found maintenance boot check script at /root/scripts/scripts/configs/maintenance-boot-check.sh"
    else
        log "WARNING: maintenance-boot-check.sh not found in either location"
        log "Tried: /root/scripts/configs/maintenance-boot-check.sh"
        log "Tried: /root/scripts/scripts/configs/maintenance-boot-check.sh"
        return 0  # Don't fail the entire cleanup
    fi
    
    # Common installation steps for either path
    chmod +x /usr/local/bin/maintenance-boot-check.sh
    
    # Create maintenance boot check service
    cat > /etc/systemd/system/maintenance-boot-check.service <<'EOF'
[Unit]
Description=Check for maintenance window on boot
After=multi-user.target
Before=lobby-display.service lobby-kiosk.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/maintenance-boot-check.sh
User=root
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable maintenance boot check
    systemctl daemon-reload
    systemctl enable maintenance-boot-check.service
    log "Maintenance boot check service installed and enabled"

    log "Cleanup and finalization completed"
}

# Reset function
reset_cleanup() {
    log "Resetting cleanup configuration"

    # Remove maintenance boot check
    systemctl disable maintenance-boot-check.service || true
    rm -f /etc/systemd/system/maintenance-boot-check.service
    rm -f /usr/local/bin/maintenance-boot-check.sh
    
    # Remove global lobby command
    rm -f /usr/local/bin/lobby

    # Remove log rotation configuration
    rm -f /etc/logrotate.d/lobby

    # Remove journal configuration
    rm -f /etc/systemd/journald.conf.d/lobby.conf

    # Recreate cleanup
    setup_cleanup

    log "Cleanup configuration reset completed"
}

# Validation function
validate_cleanup() {
    local errors=0

    # Check if global lobby command exists
    if [[ ! -L /usr/local/bin/lobby ]]; then
        log "ERROR: Global lobby command symlink not found"
        ((errors++))
    fi

    # Check if symlink points to correct location
    if [[ -L /usr/local/bin/lobby ]]; then
        local target
        target=$(readlink /usr/local/bin/lobby)
        if [[ "$target" != "/root/scripts/lobby.sh" ]]; then
            log "ERROR: Global lobby command points to wrong target (expected: /root/scripts/lobby.sh, found: $target)"
            ((errors++))
        fi
    fi

    # Check if log rotation is configured
    if [[ ! -f /etc/logrotate.d/lobby ]]; then
        log "ERROR: Log rotation configuration not found"
        ((errors++))
    fi

    # Check if journal limits are configured
    if [[ ! -f /etc/systemd/journald.conf.d/lobby.conf ]]; then
        log "ERROR: Journal size limits not configured"
        ((errors++))
    fi
    
    # Check if maintenance boot check is configured
    if [[ ! -f /usr/local/bin/maintenance-boot-check.sh ]]; then
        log "ERROR: Maintenance boot check script not found"
        ((errors++))
    fi
    
    if [[ ! -f /etc/systemd/system/maintenance-boot-check.service ]]; then
        log "ERROR: Maintenance boot check service not found"
        ((errors++))
    fi
    
    if ! systemctl is-enabled maintenance-boot-check.service >/dev/null 2>&1; then
        log "ERROR: Maintenance boot check service not enabled"
        ((errors++))
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
