#!/usr/bin/env bash
# Emergency Recovery Script for Lobby Kiosk
set -euo pipefail

LOG_FILE="/var/log/emergency-recovery.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [RECOVERY] $1" | tee -a "$LOG_FILE"
}

emergency_recovery() {
    log "🚨 EMERGENCY RECOVERY ACTIVATED"
    
    # 1. Force stop any getty services that might be running
    log "Stopping all getty services..."
    systemctl stop getty@tty1.service getty@tty2.service 2>/dev/null || true
    systemctl mask getty@tty1.service getty@tty2.service 2>/dev/null || true
    
    # 2. Clear any locks or conflicts
    log "Clearing potential conflicts..."
    pkill -f "getty" || true
    
    # 3. Restart kiosk services with clean slate
    log "Restarting kiosk services..."
    systemctl stop lobby-compositor.service lobby-app.service lobby-browser.service || true
    sleep 2
    systemctl start lobby-compositor.service lobby-app.service lobby-browser.service
    
    # 4. Wait and validate
    log "Waiting for kiosk to stabilize..."
    sleep 10
    
    # 5. Final validation
    if systemctl is-active lobby-compositor.service >/dev/null && systemctl is-active lobby-app.service >/dev/null && systemctl is-active lobby-browser.service >/dev/null && ! pgrep getty >/dev/null; then
        log "✅ Emergency recovery SUCCESSFUL"
        return 0
    else
        log "❌ Emergency recovery FAILED - manual intervention required"
        return 1
    fi
}

# Can be called directly or by monitoring service
emergency_recovery