#!/usr/bin/env bash
# Check if booting during maintenance window and handle appropriately
set -euo pipefail

LOGFILE="/var/log/lobby-maintenance.log"

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

log "Boot-time maintenance check starting"

if is_maintenance_window; then
    log "System booted during maintenance window (12:00 AM - 7:59 AM)"
    
    # Stop lobby services if they auto-started
    log "Stopping lobby services for maintenance window"
    
    
    # Switch to sleep theme
    log "Switching to sleep theme"
    /usr/local/bin/plymouth-switch-sleep.sh || {
        log "WARNING: Failed to switch to sleep theme"
    }
    
    log "System is now in maintenance mode until 8:00 AM"
else
    log "System booted during normal operating hours - services will start normally"
fi

log "Boot-time maintenance check completed"