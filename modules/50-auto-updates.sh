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
    cat > /usr/local/bin/lobby-auto-update.sh <<'UPDATESCRIPT'
#!/bin/bash

# Automatic Lobby System Updates Script with Error Recovery
# Log file location
LOG_FILE="/var/log/lobby-auto-update.log"
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
        # Check if this is during boot/early startup (network not ready yet)
        local uptime_minutes=$(awk '{print int($1/60)}' /proc/uptime)
        if [[ $uptime_minutes -lt 5 ]]; then
            log_message "WARNING: No network connectivity (system may still be starting up)"
        else
            log_message "ERROR: No network connectivity"
        fi
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

# Function to update lobby-arch project
update_lobby_arch() {
    local lobby_arch_dir="/home/lobby/Code/lobby-arch"
    if [[ -d "$lobby_arch_dir/.git" ]]; then
        log_message "Updating lobby-arch project..."
        cd "$lobby_arch_dir"
        if git pull origin main; then
            log_message "lobby-arch updated successfully"
            # Make scripts executable after update
            chmod +x scripts/modules/*.sh 2>/dev/null || true
            return 0
        else
            log_message "ERROR: Failed to update lobby-arch"
            return 1
        fi
    else
        log_message "lobby-arch directory not found or not a git repository"
        return 1
    fi
}

# Function to update lobby-display project
update_lobby_display() {
    local lobby_display_dir="/opt/lobby-display"
    local user="lobby"
    if [[ -d "$lobby_display_dir/.git" ]]; then
        log_message "Updating lobby-display project..."
        cd "$lobby_display_dir"
        if sudo -u "$user" git pull origin main; then
            log_message "lobby-display updated successfully"
            # Rebuild the project
            if sudo -u "$user" npm install && sudo -u "$user" npm run build; then
                log_message "lobby-display rebuilt successfully"
                # Restart services to use updated code
                systemctl restart lobby-app.service
                return 0
            else
                log_message "ERROR: Failed to rebuild lobby-display"
                return 1
            fi
        else
            log_message "ERROR: Failed to update lobby-display"
            return 1
        fi
    else
        log_message "lobby-display directory not found or not a git repository"
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
    
    # Update lobby projects
    update_lobby_arch
    update_lobby_display
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

    chmod +x /usr/local/bin/lobby-auto-update.sh
    
    # Create systemd service for automatic updates
    cat > /etc/systemd/system/lobby-auto-update.service <<'UPDATESERVICE'
[Unit]
Description=Automatic Lobby System Updates
# Removed network-online.target dependency to avoid boot delays
# This service should only run via timer, not during boot

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/lobby-auto-update.sh
StandardOutput=journal
StandardError=journal
TimeoutStartSec=3600

[Install]
# Removed WantedBy to prevent auto-start during boot
# Service only runs via timer scheduling
UPDATESERVICE

    # Create systemd timer for daily scheduling during maintenance window
    cat > /etc/systemd/system/lobby-auto-update.timer <<'UPDATETIMER'
[Unit]
Description=Daily Automatic Lobby Updates
Requires=lobby-auto-update.service

[Timer]
OnCalendar=*-*-* 02:00:00
RandomizedDelaySec=3600

[Install]
WantedBy=timers.target
UPDATETIMER

    # Create logrotate configuration (ensure directory exists)
    mkdir -p /etc/logrotate.d
    cat > /etc/logrotate.d/lobby-auto-update <<'LOGROTATE'
/var/log/lobby-auto-update.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
LOGROTATE

    # Enable the update timer (but don't start immediately - wait for scheduled time)
    systemctl daemon-reload
    systemctl enable lobby-auto-update.timer
    # Don't start timer during setup - it will start on next boot and run at scheduled 2 AM time
    
    log "Automatic lobby updates configured - runs daily at 2 AM with error recovery and log management"
}

# Reset function
reset_auto_updates() {
    log "Resetting automatic updates configuration"
    
    # Stop and disable timer and service
    systemctl stop lobby-auto-update.timer 2>/dev/null || true
    systemctl disable lobby-auto-update.timer 2>/dev/null || true
    systemctl stop lobby-auto-update.service 2>/dev/null || true
    systemctl disable lobby-auto-update.service 2>/dev/null || true
    
    # Remove files
    rm -f /usr/local/bin/lobby-auto-update.sh
    rm -f /etc/systemd/system/lobby-auto-update.service
    rm -f /etc/systemd/system/lobby-auto-update.timer
    rm -f /etc/logrotate.d/lobby-auto-update
    
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
    if [[ ! -f /usr/local/bin/lobby-auto-update.sh ]]; then
        log "ERROR: Update script not found"
        ((errors++))
    elif [[ ! -x /usr/local/bin/lobby-auto-update.sh ]]; then
        log "ERROR: Update script not executable"
        ((errors++))
    fi
    
    # Check systemd service
    if [[ ! -f /etc/systemd/system/lobby-auto-update.service ]]; then
        log "ERROR: Update service not found"
        ((errors++))
    fi
    
    # Check systemd timer
    if [[ ! -f /etc/systemd/system/lobby-auto-update.timer ]]; then
        log "ERROR: Update timer not found"
        ((errors++))
    fi
    
    # Check if timer is enabled and active
    if ! systemctl is-enabled lobby-auto-update.timer >/dev/null 2>&1; then
        log "ERROR: Update timer not enabled"
        ((errors++))
    fi
    
    if ! systemctl is-active lobby-auto-update.timer >/dev/null 2>&1; then
        log "ERROR: Update timer not active"
        ((errors++))
    fi
    
    # Check logrotate config
    if [[ ! -f /etc/logrotate.d/lobby-auto-update ]]; then
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