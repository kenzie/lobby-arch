#!/usr/bin/env bash
# Lobby Daily Scheduler Module

set -euo pipefail

# Module info
MODULE_NAME="Lobby Scheduler"
MODULE_VERSION="1.0"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../configs"

# Default values
USER="${LOBBY_USER:-lobby}"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODULE_NAME] $1" | tee -a "${LOBBY_LOG:-/var/log/lobby-setup.log}"
}

# Main setup function
setup_scheduler() {
    log "Setting up lobby daily scheduler"

    # Simple shutdown/startup - no complex Plymouth switching needed

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

# Stop kiosk user services (Arch Linux way)
log "Stopping lobby user services and turning off display"
sudo -u lobby systemctl --user stop lobby-kiosk.service || true
sudo -u lobby systemctl --user stop lobby-display.service || true

# Stop monitoring during downtime
log "Stopping monitoring during downtime"
systemctl stop lobby-monitor.timer || true

# Turn off display by stopping all display services
log "Turning off display for downtime"
# In Wayland, stopping the compositor effectively turns off display

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

# Display will turn on automatically when kiosk starts
log "Display will turn on when kiosk starts"

# Ensure lobby user services are running (robust restart)
log "Starting/restarting lobby user services"
sudo -u lobby systemctl --user stop lobby-display.service 2>/dev/null || true
sudo -u lobby systemctl --user start lobby-display.service
sleep 5

sudo -u lobby systemctl --user stop lobby-kiosk.service 2>/dev/null || true
sudo -u lobby systemctl --user start lobby-kiosk.service
sleep 3

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
# No dependencies - only triggered by timer, not boot

[Service]
Type=oneshot
ExecStart=/usr/local/bin/lobby-startup.sh
User=root

[Install]
# Not enabled directly - only triggered by timer
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
Persistent=false

[Install]
WantedBy=timers.target
EOF

    # Enable shutdown timer only - services should not auto-start on boot
    log "Enabling shutdown timer (startup timer disabled to prevent boot issues)"
    systemctl daemon-reload
    systemctl enable lobby-shutdown.timer
    systemctl start lobby-shutdown.timer
    # Startup timer not enabled - manual start only when needed

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

    # Startup timer should NOT be enabled - it's manually controlled
    if systemctl is-enabled lobby-startup.timer >/dev/null 2>&1; then
        log "WARNING: Startup timer is enabled but should be manually controlled"
    fi

    # Check that lobby user services are enabled (they should start automatically)
    if ! sudo -u "$USER" systemctl --user is-enabled lobby-display.service >/dev/null 2>&1; then
        log "WARNING: lobby-display.service not enabled for user $USER"
        ((errors++))
    fi

    if ! sudo -u "$USER" systemctl --user is-enabled lobby-kiosk.service >/dev/null 2>&1; then
        log "WARNING: lobby-kiosk.service not enabled for user $USER"
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
