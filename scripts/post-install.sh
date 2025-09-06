#!/usr/bin/env bash
set -euo pipefail

USER="lobby"
HOME_DIR="/home/$USER"
LOGFILE="/var/log/post-install.log"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOBBY_SCRIPT="$SCRIPT_DIR/lobby.sh"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

log "==> Starting modular post-install tasks..."

# Check if user exists
if ! id "$USER" >/dev/null 2>&1; then
    log "ERROR: User $USER does not exist"
    exit 1
fi

# Wait for network connectivity
log "Waiting for network connectivity..."
for i in {1..30}; do
    if curl -s --connect-timeout 5 https://www.google.com >/dev/null 2>&1; then
        log "Network connectivity confirmed"
        break
    fi
    if [ $i -eq 30 ]; then
        log "ERROR: Network connectivity timeout"
        exit 1
    fi
    sleep 2
done

# Set environment variables for lobby.sh
export LOBBY_USER="$USER"
export LOBBY_HOME="$HOME_DIR"
export LOBBY_LOG="$LOGFILE"

# Run modular setup using lobby.sh
log "Running modular setup using lobby.sh"
if "$LOBBY_SCRIPT" setup; then
    log "Modular setup completed successfully"
else
    log "ERROR: Modular setup failed"
    exit 1
fi

# Disable this service since it's completed
log "Disabling post-install service"
systemctl disable post-install.service

log "==> Post-install tasks complete. The system will auto-login $USER and launch Hyprland with Plymouth splash."
log "==> Use 'lobby.sh' for future configuration management."