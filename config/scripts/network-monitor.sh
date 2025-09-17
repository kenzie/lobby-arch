#!/usr/bin/env bash
# Network Monitor Script for Lobby Kiosk
# Monitors network connectivity and shows persistent mako notification when offline

set -euo pipefail

# Configuration
CHECK_INTERVAL=10  # seconds
USER="${LOBBY_USER:-lobby}"

# Test hosts (multiple for reliability)
TEST_HOSTS=(
    "8.8.8.8"
    "1.1.1.1"
    "9.9.9.9"
)

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [network-monitor] $1"
    logger -t network-monitor "$1"
}

# Check network connectivity
check_connectivity() {
    local connected=false

    for host in "${TEST_HOSTS[@]}"; do
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            connected=true
            break
        fi
    done

    echo "$connected"
}

# Send notification via mako
send_notification() {
    local title="$1"
    local body="$2"
    local urgency="$3"

    # Use sudo -u to run as the lobby user since mako runs in user session
    # The app-name "network-monitor" will trigger specific styling in mako config
    sudo -u "$USER" XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 notify-send \
        --app-name="network-monitor" \
        --urgency="$urgency" \
        "$title" "$body"
}

# Dismiss notification
dismiss_notification() {
    # Clear any existing network notifications
    sudo -u "$USER" XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 makoctl dismiss --app-name="network-monitor" 2>/dev/null || true
}

# Main monitoring loop
main() {
    log "Starting network connectivity monitor"

    local last_status=""
    local offline_notification_sent=false

    while true; do
        local current_status
        if [[ "$(check_connectivity)" == "true" ]]; then
            current_status="online"
        else
            current_status="offline"
        fi

        # Only act on status changes or initial offline state
        if [[ "$current_status" != "$last_status" ]]; then
            case "$current_status" in
                "online")
                    log "Network connectivity restored"
                    dismiss_notification
                    offline_notification_sent=false
                    ;;
                "offline")
                    log "Network connectivity lost"
                    send_notification "Offline" "No internet connection" "critical"
                    offline_notification_sent=true
                    ;;
            esac
            last_status="$current_status"
        fi

        sleep "$CHECK_INTERVAL"
    done
}

# Handle script termination
cleanup() {
    log "Network monitor stopping"
    dismiss_notification
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Start monitoring
main