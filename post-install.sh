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

# Wait for network connectivity (skip in chroot)
if [[ -z "${CHROOT_INSTALL:-}" ]]; then
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
else
    log "Skipping network check (chroot environment)"
fi

# Set environment variables for lobby.sh
export LOBBY_USER="$USER"
export LOBBY_HOME="$HOME_DIR"
export LOBBY_LOG="$LOGFILE"

# Check if modules exist and sync if missing
MODULES_DIR="$SCRIPT_DIR/modules"
if [[ ! -d "$MODULES_DIR" ]] || [[ -z "$(ls -A "$MODULES_DIR" 2>/dev/null)" ]]; then
    log "Modules directory missing or empty, attempting to sync from GitHub..."
    if "$LOBBY_SCRIPT" sync; then
        log "Successfully synced modules from GitHub"
    else
        log "ERROR: Failed to sync modules from GitHub"
        log "This may be due to network issues during installation."
        log "Try running 'sudo lobby sync' manually after boot."
        exit 1
    fi
else
    log "Modules directory exists with $(ls -1 "$MODULES_DIR"/*.sh 2>/dev/null | wc -l) module files"
fi

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
        exit_code=$?
        log "ERROR: Critical module $module failed with exit code $exit_code"
        log "Check '$LOBBY_LOG' and run 'sudo lobby validate $module' for details"
        ((critical_failures++))
    fi
done

# Run optional modules (failures are logged but don't stop installation)
for module in "${OPTIONAL_MODULES[@]}"; do
    log "Running optional module: $module"
    if "$LOBBY_SCRIPT" setup "$module"; then
        log "SUCCESS: Optional module $module completed"
    else
        exit_code=$?
        log "WARNING: Optional module $module failed with exit code $exit_code (non-critical)"
        log "Check '$LOBBY_LOG' and run 'sudo lobby validate $module' for details"
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

# Disable this service since it's completed (skip in chroot)
if [[ -z "${CHROOT_INSTALL:-}" ]]; then
    log "Disabling post-install service"
    systemctl disable post-install.service 2>/dev/null || true
else
    log "Skipping service disable (chroot environment)"
fi

log "==> Post-install tasks complete. The system will boot directly to Cage kiosk with Plymouth splash."
log "==> Use 'sudo lobby help' for system management and 'sudo lobby health' for diagnostics."
