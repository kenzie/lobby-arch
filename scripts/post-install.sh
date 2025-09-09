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

# Run modular setup using lobby.sh with better error handling
log "Running modular setup using lobby.sh"

# Define critical vs optional modules
CRITICAL_MODULES=("kiosk")
OPTIONAL_MODULES=("plymouth" "auto-updates" "monitoring" "scheduler" "cleanup")

critical_failures=0
optional_failures=0

# Run critical modules first
for module in "${CRITICAL_MODULES[@]}"; do
    log "Running critical module: $module"
    if "$LOBBY_SCRIPT" setup "$module"; then
        log "SUCCESS: Critical module $module completed"
    else
        log "ERROR: Critical module $module failed"
        ((critical_failures++))
    fi
done

# Run optional modules (failures are logged but don't stop installation)
for module in "${OPTIONAL_MODULES[@]}"; do
    log "Running optional module: $module"
    if "$LOBBY_SCRIPT" setup "$module"; then
        log "SUCCESS: Optional module $module completed"
    else
        log "WARNING: Optional module $module failed (non-critical)"
        ((optional_failures++))
    fi
done

# Evaluate results
if [[ $critical_failures -gt 0 ]]; then
    log "ERROR: $critical_failures critical module(s) failed - installation incomplete"
    log "Kiosk may not function properly. Check logs and run 'sudo lobby setup' to retry."
    exit 1
elif [[ $optional_failures -gt 0 ]]; then
    log "WARNING: $optional_failures optional module(s) failed but core kiosk should work"
    log "Run 'sudo lobby setup' to retry failed modules or 'sudo lobby health' to check status"
else
    log "SUCCESS: All modules completed successfully"
fi

# Disable this service since it's completed
log "Disabling post-install service"
systemctl disable post-install.service

log "==> Post-install tasks complete. The system will boot directly to Cage kiosk with Plymouth splash."
log "==> Use 'sudo lobby help' for system management and 'sudo lobby health' for diagnostics."
