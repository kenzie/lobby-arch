#!/usr/bin/env bash
# Boot Reliability Validator for Lobby Kiosk System
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/boot-validator.log"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [VALIDATOR] $1" | tee -a "$LOG_FILE"
}

# Check if kiosk is fully operational
validate_kiosk_state() {
    local errors=0
    log "=== Boot Validation Started ==="
    
    # 1. Check getty services are masked
    if ! systemctl list-unit-files getty@tty1.service | grep -q "masked"; then
        log "ERROR: getty@tty1.service not masked - TTY fallback possible"
        ((errors++))
    fi
    if ! systemctl list-unit-files getty@tty2.service | grep -q "masked"; then
        log "ERROR: getty@tty2.service not masked - TTY fallback possible"
        ((errors++))
    fi
    
    # 2. Check kiosk services are active
    if ! systemctl is-active lobby-compositor.service >/dev/null; then
        log "ERROR: lobby-compositor.service not active"
        ((errors++))
    fi
    if ! systemctl is-active lobby-app.service >/dev/null; then
        log "ERROR: lobby-app.service not active"
        ((errors++))
    fi
    if ! systemctl is-active lobby-browser.service >/dev/null; then
        log "ERROR: lobby-browser.service not active"
        ((errors++))
    fi
    
    # 3. Check Hyprland is running
    if ! pgrep Hyprland >/dev/null; then
        log "ERROR: Hyprland not running"
        ((errors++))
    fi
    
    # 4. Check Chromium kiosk is running
    if ! pgrep -f "chromium.*kiosk" >/dev/null; then
        log "ERROR: Chromium kiosk not running"
        ((errors++))
    fi
    
    # 5. Check display server is accessible
    if ! curl -s http://localhost:8080 >/dev/null; then
        log "ERROR: Display server not accessible"
        ((errors++))
    fi
    
    # 6. Check no TTY sessions are active (except SSH)
    local tty_count=$(who | grep -c "tty" || true)
    if [[ $tty_count -gt 0 ]]; then
        log "WARNING: $tty_count TTY sessions active - possible fallback occurred"
        who | grep "tty" | while read line; do
            log "  Active TTY: $line"
        done
    fi
    
    # 7. Check memory usage (alert if >80% of available)
    local mem_percent=$(free | awk '/^Mem:/ {printf("%.0f", $3/$2 * 100)}')
    if [[ $mem_percent -gt 80 ]]; then
        log "WARNING: High memory usage: ${mem_percent}%"
    fi
    
    # 8. Check service restart counts
    for service in lobby-compositor.service lobby-app.service lobby-browser.service; do
        local restarts=$(systemctl show $service --property=NRestarts --value)
        if [[ $restarts -gt 0 ]]; then
            log "WARNING: $service has restarted $restarts times"
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log "✅ Boot validation PASSED - Kiosk fully operational"
        return 0
    else
        log "❌ Boot validation FAILED with $errors critical errors"
        return 1
    fi
}

# Stress test boot reliability
stress_test_boot() {
    local test_count=${1:-10}
    log "=== Starting Boot Stress Test ($test_count iterations) ==="
    
    local failures=0
    for i in $(seq 1 $test_count); do
        log "Test iteration $i/$test_count"
        
        # Restart kiosk services
        systemctl restart lobby-compositor.service lobby-app.service lobby-browser.service
        
        # Wait for restart
        sleep 5
        
        # Validate state
        if ! validate_kiosk_state >/dev/null 2>&1; then
            ((failures++))
            log "❌ Test $i FAILED"
        else
            log "✅ Test $i PASSED"
        fi
        
        # Brief pause between tests
        sleep 2
    done
    
    local success_rate=$(( (test_count - failures) * 100 / test_count ))
    log "=== Stress Test Complete ==="
    log "Success Rate: $success_rate% ($((test_count - failures))/$test_count)"
    
    if [[ $failures -eq 0 ]]; then
        log "🎉 All stress tests PASSED - Boot reliability confirmed"
        return 0
    else
        log "⚠️  $failures tests FAILED - Boot reliability issues detected"
        return 1
    fi
}

# Monitor boot process for issues
monitor_boot_health() {
    log "=== Starting Boot Health Monitor ==="
    
    # Check every 30 seconds
    while true; do
        if ! validate_kiosk_state >/dev/null 2>&1; then
            log "🚨 ALERT: Kiosk health check failed - investigating..."
            
            # Get detailed status for debugging
            for service in lobby-compositor.service lobby-app.service lobby-browser.service; do
                systemctl status $service --no-pager -l | head -20 | while read line; do
                    log "  STATUS ($service): $line"
                done
            done
            
            # Check for common issues
            if pgrep getty >/dev/null; then
                log "🚨 CRITICAL: Getty services are running - TTY fallback active"
            fi
            
            # Attempt automatic recovery
            log "Attempting automatic recovery..."
            systemctl restart lobby-compositor.service lobby-app.service lobby-browser.service
            sleep 10
            
            if validate_kiosk_state >/dev/null 2>&1; then
                log "✅ Automatic recovery successful"
            else
                log "❌ Automatic recovery failed - manual intervention required"
            fi
        fi
        
        sleep 30
    done
}

# Main command interface
case "${1:-validate}" in
    "validate")
        validate_kiosk_state
        ;;
    "stress")
        stress_test_boot "${2:-10}"
        ;;
    "monitor")
        monitor_boot_health
        ;;
    *)
        echo "Usage: $0 {validate|stress [count]|monitor}"
        echo "  validate - Check current kiosk state"
        echo "  stress   - Perform reliability stress test"
        echo "  monitor  - Continuous health monitoring"
        exit 1
        ;;
esac