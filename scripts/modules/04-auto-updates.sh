#!/usr/bin/env bash
# Automatic Updates Configuration Module

set -euo pipefail

# Module info
MODULE_NAME="Auto-updates Setup"
MODULE_VERSION="1.0"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODULE_NAME] $1" | tee -a "${LOBBY_LOG:-/var/log/lobby-setup.log}"
}

# Main setup function
setup_auto_updates() {
    log "Setting up automatic pacman updates"
    
    # Create the update script
    cat > /usr/local/bin/pacman-auto-update.sh <<'UPDATESCRIPT'
#!/bin/bash

# Automatic Pacman Updates Script with Error Recovery
# Log file location
LOG_FILE="/var/log/pacman-auto-update.log"
MAX_LOG_SIZE=10485760  # 10MB in bytes

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to rotate log if too large
rotate_log() {
    if [[ -f "$LOG_FILE" && $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null) -gt $MAX_LOG_SIZE ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        log_message "Log rotated due to size limit"
    fi
}

# Function to clean up old logs (keep last 5 rotated logs)
cleanup_old_logs() {
    find /var/log -name "pacman-auto-update.log.*" -type f | sort -r | tail -n +6 | xargs -r rm
}

# Function to handle pacman lock
handle_pacman_lock() {
    local lock_file="/var/lib/pacman/db.lck"
    if [[ -f "$lock_file" ]]; then
        log_message "Pacman lock file detected, checking if pacman is running..."
        if ! pgrep -x pacman >/dev/null; then
            log_message "No pacman process found, removing stale lock file"
            rm -f "$lock_file"
        else
            log_message "Pacman is running, waiting for completion..."
            while [[ -f "$lock_file" ]]; do
                sleep 30
            done
        fi
    fi
}

# Function to check system health before update
pre_update_checks() {
    log_message "Performing pre-update system checks..."
    
    # Check available disk space (need at least 1GB free)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 1048576 ]]; then
        log_message "ERROR: Insufficient disk space for updates (less than 1GB free)"
        return 1
    fi
    
    # Check if network is available
    if ! ping -c 1 archlinux.org >/dev/null 2>&1; then
        log_message "ERROR: No network connectivity"
        return 1
    fi
    
    log_message "Pre-update checks passed"
    return 0
}

# Function to perform the update
perform_update() {
    log_message "Starting automatic system update..."
    
    # Sync package databases
    if ! pacman -Sy --noconfirm; then
        log_message "ERROR: Failed to sync package databases"
        return 1
    fi
    
    # Check for updates
    local updates=$(pacman -Qu | wc -l)
    if [[ $updates -eq 0 ]]; then
        log_message "No updates available"
        return 0
    fi
    
    log_message "Found $updates package(s) to update"
    
    # Perform the update
    if pacman -Su --noconfirm; then
        log_message "System update completed successfully ($updates packages updated)"
        
        # Clean package cache (keep last 3 versions)
        if paccache -r -k3; then
            log_message "Package cache cleaned"
        fi
        
        return 0
    else
        log_message "ERROR: System update failed"
        return 1
    fi
}

# Function to handle post-update tasks
post_update_tasks() {
    # Check if reboot is needed (kernel update)
    if [[ -f /usr/lib/modules/$(uname -r) ]]; then
        log_message "No reboot required"
    else
        log_message "WARNING: Reboot may be required due to kernel update"
        # Create a flag file for manual inspection
        touch /var/log/reboot-required
    fi
    
    # Update file database
    if command -v updatedb >/dev/null; then
        updatedb 2>/dev/null && log_message "File database updated"
    fi
}

# Main execution
main() {
    rotate_log
    cleanup_old_logs
    
    log_message "=== Automatic Update Session Started ==="
    
    # Perform pre-update checks
    if ! pre_update_checks; then
        log_message "Pre-update checks failed, aborting update"
        exit 1
    fi
    
    # Handle any existing pacman lock
    handle_pacman_lock
    
    # Attempt the update with retries
    local max_retries=3
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        if perform_update; then
            post_update_tasks
            log_message "=== Update Session Completed Successfully ==="
            exit 0
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                log_message "Update failed, retry $retry_count/$max_retries in 60 seconds..."
                sleep 60
            fi
        fi
    done
    
    log_message "=== Update Session Failed After $max_retries Attempts ==="
    exit 1
}

# Execute main function
main "$@"
UPDATESCRIPT

    chmod +x /usr/local/bin/pacman-auto-update.sh
    
    # Create systemd service for automatic updates
    cat > /etc/systemd/system/pacman-auto-update.service <<'UPDATESERVICE'
[Unit]
Description=Automatic Pacman System Updates
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/pacman-auto-update.sh
StandardOutput=journal
StandardError=journal
TimeoutStartSec=3600

[Install]
WantedBy=multi-user.target
UPDATESERVICE

    # Create systemd timer for weekly scheduling
    cat > /etc/systemd/system/pacman-auto-update.timer <<'UPDATETIMER'
[Unit]
Description=Weekly Automatic Pacman Updates
Requires=pacman-auto-update.service

[Timer]
OnCalendar=weekly
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
UPDATETIMER

    # Create logrotate configuration
    cat > /etc/logrotate.d/pacman-auto-update <<'LOGROTATE'
/var/log/pacman-auto-update.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
LOGROTATE

    # Enable and start the update timer
    systemctl daemon-reload
    systemctl enable pacman-auto-update.timer
    systemctl start pacman-auto-update.timer
    
    log "Automatic pacman updates configured - runs weekly with error recovery and log management"
}

# Reset function
reset_auto_updates() {
    log "Resetting automatic updates configuration"
    
    # Stop and disable timer and service
    systemctl stop pacman-auto-update.timer 2>/dev/null || true
    systemctl disable pacman-auto-update.timer 2>/dev/null || true
    systemctl stop pacman-auto-update.service 2>/dev/null || true
    systemctl disable pacman-auto-update.service 2>/dev/null || true
    
    # Remove files
    rm -f /usr/local/bin/pacman-auto-update.sh
    rm -f /etc/systemd/system/pacman-auto-update.service
    rm -f /etc/systemd/system/pacman-auto-update.timer
    rm -f /etc/logrotate.d/pacman-auto-update
    
    # Reload systemd
    systemctl daemon-reload
    
    # Recreate configuration
    setup_auto_updates
    
    log "Automatic updates configuration reset completed"
}

# Validation function
validate_auto_updates() {
    local errors=0
    
    # Check if script exists and is executable
    if [[ ! -f /usr/local/bin/pacman-auto-update.sh ]]; then
        log "ERROR: Update script not found"
        ((errors++))
    elif [[ ! -x /usr/local/bin/pacman-auto-update.sh ]]; then
        log "ERROR: Update script not executable"
        ((errors++))
    fi
    
    # Check systemd service
    if [[ ! -f /etc/systemd/system/pacman-auto-update.service ]]; then
        log "ERROR: Update service not found"
        ((errors++))
    fi
    
    # Check systemd timer
    if [[ ! -f /etc/systemd/system/pacman-auto-update.timer ]]; then
        log "ERROR: Update timer not found"
        ((errors++))
    fi
    
    # Check if timer is enabled and active
    if ! systemctl is-enabled pacman-auto-update.timer >/dev/null 2>&1; then
        log "ERROR: Update timer not enabled"
        ((errors++))
    fi
    
    if ! systemctl is-active pacman-auto-update.timer >/dev/null 2>&1; then
        log "ERROR: Update timer not active"
        ((errors++))
    fi
    
    # Check logrotate config
    if [[ ! -f /etc/logrotate.d/pacman-auto-update ]]; then
        log "ERROR: Logrotate configuration not found"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log "Auto-updates validation passed"
        return 0
    else
        log "Auto-updates validation failed with $errors errors"
        return 1
    fi
}

# Command line interface
case "${1:-setup}" in
    "setup")
        setup_auto_updates
        ;;
    "reset")
        reset_auto_updates
        ;;
    "validate")
        validate_auto_updates
        ;;
    *)
        echo "Usage: $0 {setup|reset|validate}"
        exit 1
        ;;
esac