#!/usr/bin/env bash
# Health Monitor Script for Lobby Kiosk
# Monitors network connectivity and browser health with mako notifications

set -euo pipefail

# Configuration
CHECK_INTERVAL=300  # seconds (5 minutes) - sufficient for offline-first kiosk system
USER="${LOBBY_USER:-lobby}"

# Get runtime directory dynamically
LOBBY_UID=$(id -u "$USER" 2>/dev/null || echo "1000")
RUNTIME_DIR="/run/user/$LOBBY_UID"

# Test hosts (multiple for reliability)
TEST_HOSTS=(
    "8.8.8.8"
    "1.1.1.1"
    "9.9.9.9"
)

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [health-monitor] $1"
    logger -t health-monitor "$1"
}

# Check network connectivity
check_network() {
    local connected=false

    for host in "${TEST_HOSTS[@]}"; do
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            connected=true
            break
        fi
    done

    echo "$connected"
}

# Check browser health
check_browser() {
    # Check if browser process is running
    if pgrep -f "chromium.*kiosk" >/dev/null 2>&1; then
        echo "true"
    else
        echo "false"
    fi
}

# Check app availability
check_app() {
    if curl -s --connect-timeout 3 http://localhost:8080 >/dev/null 2>&1; then
        echo "true"
    else
        echo "false"
    fi
}

# Check compositor health (Wayland socket existence)
check_compositor() {
    # Check if Wayland socket exists and compositor service is active
    if [[ -S "$RUNTIME_DIR/wayland-1" ]] && systemctl is-active lobby-compositor.service >/dev/null 2>&1; then
        echo "true"
    else
        echo "false"
    fi
}

# Check critical services
check_services() {
    local services=("lobby-browser.service" "lobby-compositor.service" "lobby-app.service")
    local all_running=true

    for service in "${services[@]}"; do
        if ! systemctl is-active "$service" >/dev/null 2>&1; then
            all_running=false
            break
        fi
    done

    echo "$all_running"
}

# Send notification via mako
send_notification() {
    local title="$1"
    local body="$2"
    local urgency="$3"
    local app_name="${4:-health-monitor}"

    # Use sudo -u to run as the lobby user since mako runs in user session
    sudo -u "$USER" XDG_RUNTIME_DIR="$RUNTIME_DIR" WAYLAND_DISPLAY=wayland-1 notify-send \
        --app-name="$app_name" \
        --urgency="$urgency" \
        "$title" "$body"
}

# Dismiss notifications by app name
dismiss_notification() {
    local app_name="${1:-health-monitor}"

    # Dismiss all notifications from specific app by finding their IDs
    local notification_ids
    notification_ids=$(sudo -u "$USER" XDG_RUNTIME_DIR="$RUNTIME_DIR" WAYLAND_DISPLAY=wayland-1 makoctl list 2>/dev/null | \
        awk -v app="$app_name" '/^Notification [0-9]+:/ { id = $2; gsub(/:/, "", id) } /App name: / && $3 == app { print id }' || true)

    if [[ -n "$notification_ids" ]]; then
        while IFS= read -r id; do
            [[ -n "$id" ]] && sudo -u "$USER" XDG_RUNTIME_DIR="$RUNTIME_DIR" WAYLAND_DISPLAY=wayland-1 makoctl dismiss -n "$id" 2>/dev/null || true
        done <<< "$notification_ids"
    fi
}

# Restart browser service
restart_browser() {
    log "Browser health check failed - restarting browser service"
    systemctl restart lobby-browser.service
}

# Restart app service
restart_app() {
    log "App health check failed - restarting app service"
    systemctl restart lobby-app.service
}

# Restart compositor service
restart_compositor() {
    log "Compositor health check failed - restarting compositor service"
    systemctl restart lobby-compositor.service
}

# Main monitoring loop
main() {
    log "Starting health monitor (network + browser + app + compositor)"

    local last_network_status=""
    local last_browser_status=""
    local last_app_status=""
    local last_compositor_status=""

    while true; do
        # Check network connectivity
        local network_status
        if [[ "$(check_network)" == "true" ]]; then
            network_status="online"
        else
            network_status="offline"
        fi

        # Handle network status changes
        if [[ "$network_status" != "$last_network_status" ]]; then
            case "$network_status" in
                "online")
                    log "Network connectivity restored"
                    dismiss_notification "health-monitor"
                    ;;
                "offline")
                    log "Network connectivity lost"
                    send_notification "Offline" "No internet connection" "critical" "health-monitor"
                    ;;
            esac
            last_network_status="$network_status"
        fi

        # Check compositor health first (browser depends on it)
        local compositor_status
        if [[ "$(check_compositor)" == "true" ]]; then
            compositor_status="running"
        else
            compositor_status="stopped"
        fi

        # Handle compositor status changes
        if [[ "$compositor_status" != "$last_compositor_status" ]]; then
            case "$compositor_status" in
                "running")
                    log "Compositor and Wayland socket detected"
                    dismiss_notification "health-monitor"
                    ;;
                "stopped")
                    log "Compositor or Wayland socket missing - attempting restart"
                    restart_compositor
                    send_notification "Display Critical" "Restarting compositor" "critical" "health-monitor"
                    ;;
            esac
            last_compositor_status="$compositor_status"
        fi

        # Check browser health (only if compositor is running)
        local browser_status
        if [[ "$compositor_status" == "running" && "$(check_browser)" == "true" ]]; then
            browser_status="running"
        else
            browser_status="stopped"
        fi

        # Handle browser status changes
        if [[ "$browser_status" != "$last_browser_status" ]]; then
            case "$browser_status" in
                "running")
                    log "Browser process detected"
                    dismiss_notification "health-monitor"
                    ;;
                "stopped")
                    if [[ "$compositor_status" == "running" ]]; then
                        log "Browser process missing - attempting restart"
                        restart_browser
                        send_notification "Display Issue" "Restarting browser" "normal" "health-monitor"
                    else
                        log "Browser process missing but compositor not ready - skipping browser restart"
                    fi
                    ;;
            esac
            last_browser_status="$browser_status"
        fi

        # Check app availability
        local app_status
        if [[ "$(check_app)" == "true" ]]; then
            app_status="responding"
        else
            app_status="not_responding"
        fi

        # Handle app status changes
        if [[ "$app_status" != "$last_app_status" && "$app_status" == "not_responding" ]]; then
            log "App not responding - attempting restart"
            restart_app
            send_notification "App Issue" "Restarting display app" "normal" "health-monitor"
            last_app_status="$app_status"
        elif [[ "$app_status" == "responding" && "$last_app_status" == "not_responding" ]]; then
            log "App responding again"
            last_app_status="$app_status"
        fi

        sleep "$CHECK_INTERVAL"
    done
}

# Handle script termination
cleanup() {
    log "Health monitor stopping"
    dismiss_notification "health-monitor"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Start monitoring
main