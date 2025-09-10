#!/usr/bin/env bash
# Lobby Monitoring System Module

set -euo pipefail

# Module info
MODULE_NAME="Lobby Monitoring"
MODULE_VERSION="1.0"

# Default values
USER="${LOBBY_USER:-lobby}"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODULE_NAME] $1" | tee -a "${LOBBY_LOG:-/var/log/lobby-setup.log}"
}

# Main setup function
setup_monitoring() {
    log "Setting up lobby monitoring system"
    
    # Create monitoring script
    log "Creating lobby monitor script"
    cat > /usr/local/bin/lobby-monitor.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

LOGFILE="/var/log/lobby-monitor.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

# Check if we're in maintenance window (12:00 AM - 7:59 AM)
is_maintenance_window() {
    local hour=$(date +%H)
    # Convert to integer and check range
    hour=$((10#$hour))
    # Maintenance window: 0-7 (midnight to 7:59 AM)
    [[ $hour -ge 0 && $hour -lt 8 ]]
}

check_service() {
    local service="$1"
    if ! systemctl is-active --quiet "$service"; then
        log "WARNING: $service is not running, attempting restart"
        systemctl restart "$service"
        sleep 5
        if systemctl is-active --quiet "$service"; then
            log "SUCCESS: $service restarted successfully"
        else
            log "ERROR: Failed to restart $service"
            return 1
        fi
    fi
}

check_url() {
    local url="$1"
    if ! curl -s --max-time 10 "$url" >/dev/null; then
        log "WARNING: $url is not responding"
        return 1
    fi
}

# Skip monitoring during maintenance window
if is_maintenance_window; then
    log "INFO: In maintenance window (12:00 AM - 7:59 AM), skipping service monitoring"
    exit 0
fi

# Monitor services
check_service "lobby-display.service" 
check_service "lobby-kiosk.service"

# Check if lobby-display is responding
if ! check_url "http://localhost:8080"; then
    log "WARNING: Lobby display app not responding, restarting services"
    systemctl restart lobby-display.service
    sleep 10
    systemctl restart lobby-kiosk.service
fi

# Check if Hyprland compositor and Chromium are running
if ! pgrep "Hyprland" >/dev/null; then
    log "WARNING: Hyprland compositor not running, restarting kiosk service"
    systemctl restart lobby-kiosk.service
elif ! pgrep "chromium" >/dev/null; then
    log "WARNING: Chromium not running, restarting kiosk service"  
    systemctl restart lobby-kiosk.service
fi

log "Monitor check completed"
EOF
    
    chmod +x /usr/local/bin/lobby-monitor.sh
    
    # Create monitoring service
    log "Creating monitoring service"
    cat > /etc/systemd/system/lobby-monitor.service <<EOF
[Unit]
Description=Lobby System Monitor
After=lobby-kiosk.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/lobby-monitor.sh
User=root

[Install]
WantedBy=multi-user.target
EOF
    
    # Create monitoring timer (every 2 minutes)
    log "Creating monitoring timer"
    cat > /etc/systemd/system/lobby-monitor.timer <<EOF
[Unit]
Description=Run Lobby Monitor Every 2 Minutes
Requires=lobby-monitor.service

[Timer]
OnCalendar=*:*:00/2
Persistent=true
# Delay initial run to allow kiosk to fully initialize during boot
OnBootSec=3min

[Install]
WantedBy=timers.target
EOF
    
    # Enable monitoring
    log "Enabling monitoring system"
    systemctl daemon-reload
    systemctl enable lobby-monitor.timer
    systemctl start lobby-monitor.timer
    
    log "Monitoring system setup completed"
}

# Reset function
reset_monitoring() {
    log "Resetting monitoring system"
    
    # Stop and disable timer
    systemctl stop lobby-monitor.timer || true
    systemctl disable lobby-monitor.timer || true
    
    # Remove files
    rm -f /etc/systemd/system/lobby-monitor.service
    rm -f /etc/systemd/system/lobby-monitor.timer
    rm -f /usr/local/bin/lobby-monitor.sh
    
    systemctl daemon-reload
    
    # Recreate
    setup_monitoring
    
    log "Monitoring system reset completed"
}

# Validation function
validate_monitoring() {
    local errors=0
    
    # Check if files exist
    if [[ ! -f /usr/local/bin/lobby-monitor.sh ]]; then
        log "ERROR: Monitor script not found"
        ((errors++))
    fi
    
    if [[ ! -x /usr/local/bin/lobby-monitor.sh ]]; then
        log "ERROR: Monitor script not executable"
        ((errors++))
    fi
    
    if [[ ! -f /etc/systemd/system/lobby-monitor.timer ]]; then
        log "ERROR: Monitor timer not found"
        ((errors++))
    fi
    
    # Check if timer is enabled and active
    if ! systemctl is-enabled lobby-monitor.timer >/dev/null 2>&1; then
        log "ERROR: Monitor timer not enabled"
        ((errors++))
    fi
    
    if ! systemctl is-active lobby-monitor.timer >/dev/null 2>&1; then
        log "ERROR: Monitor timer not active"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log "Monitoring validation passed"
        return 0
    else
        log "Monitoring validation failed with $errors errors"
        return 1
    fi
}

# Command line interface
case "${1:-setup}" in
    "setup")
        setup_monitoring
        ;;
    "reset")
        reset_monitoring
        ;;
    "validate")
        validate_monitoring
        ;;
    *)
        echo "Usage: $0 {setup|reset|validate}"
        exit 1
        ;;
esac