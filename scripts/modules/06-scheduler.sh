#!/usr/bin/env bash
# Lobby Daily Scheduler Module

set -euo pipefail

# Module info
MODULE_NAME="Lobby Scheduler"
MODULE_VERSION="1.0"

# Default values
USER="${LOBBY_USER:-lobby}"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODULE_NAME] $1" | tee -a "${LOBBY_LOG:-/var/log/lobby-setup.log}"
}

# Main setup function
setup_scheduler() {
    log "Setting up lobby daily scheduler"
    
    # Create shutdown script
    log "Creating shutdown script"
    cat > /usr/local/bin/lobby-shutdown.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

LOGFILE="/var/log/lobby-scheduler.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

log "Starting nightly shutdown sequence"

# Stop kiosk services (Wayland/Cage architecture)
log "Stopping lobby kiosk services"
systemctl stop lobby-kiosk.service || true
systemctl stop lobby-display.service || true

# Stop monitoring during maintenance window
log "Stopping monitoring during shutdown"
systemctl stop lobby-monitor.timer || true

# Show Plymouth screen during maintenance window
log "Showing Plymouth splash for maintenance window"
systemctl start plymouth-poweroff.service || true

log "Nightly shutdown completed"
EOF
    
    chmod +x /usr/local/bin/lobby-shutdown.sh
    
    # Create startup script for 8 AM daily restart (maintenance window)
    log "Creating startup script for daily 8 AM restart"
    cat > /usr/local/bin/lobby-startup.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

LOGFILE="/var/log/lobby-scheduler.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

log "Starting morning startup sequence"

# Ensure lobby display app is running
log "Starting lobby display service"
systemctl start lobby-display.service
sleep 5

# Ensure kiosk is running (Wayland/Cage architecture)
log "Starting lobby kiosk"
systemctl start lobby-kiosk.service
sleep 2

# Hide Plymouth screen and resume monitoring
log "Hiding Plymouth splash"
plymouth quit || true
systemctl stop plymouth-poweroff.service || true

# Resume monitoring
log "Starting monitoring system"
systemctl start lobby-monitor.timer

log "Morning startup completed"
EOF
    
    chmod +x /usr/local/bin/lobby-startup.sh
    
    # Create shutdown service
    log "Creating shutdown service"
    cat > /etc/systemd/system/lobby-shutdown.service <<EOF
[Unit]
Description=Lobby Daily Shutdown
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/lobby-shutdown.sh
User=root

[Install]
WantedBy=multi-user.target
EOF
    
    # Create startup service for 8 AM daily restart
    log "Creating startup service"
    cat > /etc/systemd/system/lobby-startup.service <<EOF
[Unit]
Description=Lobby Daily Startup
After=multi-user.target graphical.target
# Don't block boot - this is for scheduled restart, not boot startup

[Service]
Type=oneshot
ExecStart=/usr/local/bin/lobby-startup.sh
User=root

[Install]
# Note: Not WantedBy multi-user.target - only triggered by timer
WantedBy=lobby-startup.timer
EOF
    
    # Create shutdown timer (11:59 PM daily)
    log "Creating shutdown timer"
    cat > /etc/systemd/system/lobby-shutdown.timer <<EOF
[Unit]
Description=Daily Lobby Shutdown at 11:59 PM
Requires=lobby-shutdown.service

[Timer]
OnCalendar=*-*-* 23:59:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Create startup timer (8:00 AM daily) 
    log "Creating startup timer"
    cat > /etc/systemd/system/lobby-startup.timer <<EOF
[Unit]
Description=Daily Lobby Startup at 8:00 AM
Requires=lobby-startup.service

[Timer]
OnCalendar=*-*-* 08:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Enable both timers for maintenance window
    log "Enabling daily schedule timers"
    systemctl daemon-reload
    systemctl enable lobby-shutdown.timer
    systemctl enable lobby-startup.timer
    systemctl start lobby-shutdown.timer
    systemctl start lobby-startup.timer
    
    log "Daily scheduler setup completed"
}

# Reset function
reset_scheduler() {
    log "Resetting scheduler system"
    
    # Stop and disable shutdown timer
    systemctl stop lobby-shutdown.timer || true
    systemctl disable lobby-shutdown.timer || true
    
    # Stop and disable startup timer
    systemctl stop lobby-startup.timer || true
    systemctl disable lobby-startup.timer || true
    
    # Remove all scheduler files
    rm -f /etc/systemd/system/lobby-shutdown.service
    rm -f /etc/systemd/system/lobby-shutdown.timer
    rm -f /usr/local/bin/lobby-shutdown.sh
    rm -f /etc/systemd/system/lobby-startup.service
    rm -f /etc/systemd/system/lobby-startup.timer
    rm -f /usr/local/bin/lobby-startup.sh
    
    systemctl daemon-reload
    
    # Recreate
    setup_scheduler
    
    log "Scheduler system reset completed"
}

# Validation function
validate_scheduler() {
    local errors=0
    
    # Check if scripts exist and are executable
    if [[ ! -f /usr/local/bin/lobby-shutdown.sh ]]; then
        log "ERROR: Shutdown script not found"
        ((errors++))
    fi
    
    if [[ ! -f /usr/local/bin/lobby-startup.sh ]]; then
        log "ERROR: Startup script not found"
        ((errors++))
    fi
    
    if [[ ! -x /usr/local/bin/lobby-shutdown.sh ]]; then
        log "ERROR: Shutdown script not executable"
        ((errors++))
    fi
    
    if [[ ! -x /usr/local/bin/lobby-startup.sh ]]; then
        log "ERROR: Startup script not executable"
        ((errors++))
    fi
    
    # Check if timers exist and are enabled
    if [[ ! -f /etc/systemd/system/lobby-shutdown.timer ]]; then
        log "ERROR: Shutdown timer not found"
        ((errors++))
    fi
    
    if [[ ! -f /etc/systemd/system/lobby-startup.timer ]]; then
        log "ERROR: Startup timer not found"
        ((errors++))
    fi
    
    if ! systemctl is-enabled lobby-shutdown.timer >/dev/null 2>&1; then
        log "ERROR: Shutdown timer not enabled"
        ((errors++))
    fi
    
    if ! systemctl is-enabled lobby-startup.timer >/dev/null 2>&1; then
        log "ERROR: Startup timer not enabled"
        ((errors++))
    fi
    
    # Check that lobby services are enabled (they should start automatically)
    if ! systemctl is-enabled lobby-display.service >/dev/null 2>&1; then
        log "WARNING: lobby-display.service not enabled"
        ((errors++))
    fi
    
    if ! systemctl is-enabled lobby-kiosk.service >/dev/null 2>&1; then
        log "WARNING: lobby-kiosk.service not enabled"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log "Scheduler validation passed"
        return 0
    else
        log "Scheduler validation failed with $errors errors"
        return 1
    fi
}

# Command line interface
case "${1:-setup}" in
    "setup")
        setup_scheduler
        ;;
    "reset")
        reset_scheduler
        ;;
    "validate")
        validate_scheduler
        ;;
    *)
        echo "Usage: $0 {setup|reset|validate}"
        exit 1
        ;;
esac