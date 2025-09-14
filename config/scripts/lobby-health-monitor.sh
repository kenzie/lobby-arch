#!/bin/bash
# Lobby Health Monitor - Detects and recovers from kiosk failures

HEALTH_LOG="/var/log/lobby-health.log"
MAX_FAILURES=3
FAILURE_COUNT=0

log_health() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [HEALTH] $1" | tee -a "$HEALTH_LOG"
}

check_kiosk_health() {
    # Check if all critical services are running
    if ! systemctl is-active lobby-compositor.service >/dev/null; then
        log_health "CRITICAL: Compositor service is not running"
        return 1
    fi

    if ! systemctl is-active lobby-app.service >/dev/null; then
        log_health "CRITICAL: App service is not running"
        return 1
    fi

    if ! systemctl is-active lobby-browser.service >/dev/null; then
        log_health "CRITICAL: Browser service is not running"
        return 1
    fi

    # Check if Wayland display is available
    if [ ! -S /run/user/1000/wayland-1 ]; then
        log_health "CRITICAL: Wayland display socket missing"
        return 1
    fi

    # Check if browser can connect to app
    if ! curl -s --max-time 5 http://localhost:8080 >/dev/null; then
        log_health "CRITICAL: App not responding on localhost:8080"
        return 1
    fi

    # Check if browser has GUI processes running
    if ! pgrep -f "chromium.*kiosk" >/dev/null; then
        log_health "CRITICAL: Browser kiosk process not found"
        return 1
    fi

    log_health "OK: All kiosk components healthy"
    return 0
}

recover_kiosk() {
    log_health "RECOVERY: Attempting kiosk recovery (failure $FAILURE_COUNT/$MAX_FAILURES)"

    # Restart services in order
    systemctl restart lobby-compositor.service
    sleep 5
    systemctl restart lobby-app.service
    sleep 3
    systemctl restart lobby-browser.service

    log_health "RECOVERY: Services restarted, waiting for stabilization"
    sleep 15
}

# Main health check loop
while true; do
    if check_kiosk_health; then
        FAILURE_COUNT=0
        sleep 30
    else
        ((FAILURE_COUNT++))

        if [ $FAILURE_COUNT -le $MAX_FAILURES ]; then
            recover_kiosk
            sleep 30
        else
            log_health "FATAL: Max failures reached ($MAX_FAILURES), stopping recovery attempts"
            systemctl reboot
            exit 1
        fi
    fi
done
