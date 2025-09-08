#!/usr/bin/env bash
set -euo pipefail

USER="lobby"
HOME_DIR="/home/$USER"
LOGFILE="/var/log/post-install.log"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

log "==> Starting post-install tasks..."

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

# Set environment variables for modules
export LOBBY_USER="$USER"
export LOBBY_HOME="$HOME_DIR"
export LOBBY_LOG="$LOGFILE"

# Module directory
MODULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/modules"

# Execute modules in order
log "==> Running lobby setup modules..."

# Module execution function
run_module() {
    local module="$1"
    local module_path="$MODULES_DIR/$module"
    
    if [[ -f "$module_path" && -x "$module_path" ]]; then
        log "Running module: $module"
        if "$module_path" setup; then
            log "Module $module completed successfully"
        else
            log "ERROR: Module $module failed"
            return 1
        fi
    else
        log "WARNING: Module $module not found or not executable: $module_path"
        return 1
    fi
}

# Run modules in order
# Note: 01-autologin.sh and 02-hyprland.sh have been removed
run_module "02-kiosk.sh"          # Chromium kiosk setup
run_module "03-plymouth.sh"       # Plymouth boot display
run_module "04-auto-updates.sh"   # Automated updates
run_module "05-monitoring.sh"     # Service monitoring
run_module "06-scheduler.sh"      # Daily schedule
run_module "99-cleanup.sh"        # Final cleanup

# Validate all modules
log "==> Validating module configurations..."
validation_errors=0

for module in "02-kiosk.sh" "03-plymouth.sh" "04-auto-updates.sh" "05-monitoring.sh" "06-scheduler.sh" "99-cleanup.sh"; do
    module_path="$MODULES_DIR/$module"
    if [[ -f "$module_path" && -x "$module_path" ]]; then
        log "Validating module: $module"
        if "$module_path" validate; then
            log "Module $module validation passed"
        else
            log "ERROR: Module $module validation failed"
            ((validation_errors++))
        fi
    fi
done

if [[ $validation_errors -eq 0 ]]; then
    log "==> All module validations passed"
else
    log "WARNING: $validation_errors module validation(s) failed"
fi

# Final system status
log "==> Checking final system status..."
log "Enabled systemd services:"
systemctl list-unit-files --state=enabled | grep -E "(lobby|xserver)" || log "No lobby services found"

log "Active systemd timers:"
systemctl list-timers | grep -E "(lobby|update)" || log "No lobby timers found"

log "==> Post-install setup completed"
log "System is ready for kiosk operation"
log "Services will start automatically on boot"
log "Daily schedule: Shutdown at 11:59 PM, Startup at 8:00 AM"
log "Updates run daily at 2:00 AM"