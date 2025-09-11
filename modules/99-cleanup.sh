#!/usr/bin/env bash
# Cleanup and Finalization Module

set -euo pipefail

# Module info
MODULE_NAME="Cleanup"
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

    # Maintenance boot check removed - simplified system just uses scheduler

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

    # Maintenance boot check removed - simplified system just uses scheduler

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
