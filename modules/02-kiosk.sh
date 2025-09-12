#!/usr/bin/env bash
# Lobby Kiosk Configuration Module (Modular Architecture)
# This module orchestrates the new modular kiosk setup

set -euo pipefail

# Module info  
MODULE_NAME="Lobby Kiosk Setup (Modular)"
MODULE_VERSION="3.0"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODULE_NAME] $1" | tee -a "${LOBBY_LOG:-/var/log/lobby-setup.log}"
}

# Main setup function - orchestrates modular components
setup_kiosk() {
    log "Setting up lobby kiosk using modular architecture"
    log "Architecture: Sway compositor + independent Chromium + Vue.js app"

    local errors=0

    # Run modules in dependency order
    local modules=(
        "30-app.sh"         # Vue.js application (no dependencies)
        "20-compositor.sh"  # Sway compositor 
        "40-browser.sh"     # Chromium browser (depends on compositor + app)
    )

    for module in "${modules[@]}"; do
        local module_path="$SCRIPT_DIR/$module"
        
        if [[ -f "$module_path" ]]; then
            log "Running module: $module"
            
            # Make executable
            chmod +x "$module_path"
            
            if "$module_path" setup; then
                log "✅ Module $module completed successfully"
            else
                log "❌ Module $module failed"
                ((errors++))
            fi
        else
            log "⚠️  Module $module not found at $module_path"
            ((errors++))
        fi
    done

    # Set default boot target
    log "Setting graphical boot target"
    systemctl set-default graphical.target

    # Final validation
    if [[ $errors -eq 0 ]]; then
        log "✅ Modular kiosk setup completed successfully"
        log "Services: lobby-app.service, lobby-compositor.service, lobby-browser.service"
        return 0
    else
        log "❌ Modular kiosk setup failed with $errors errors"
        return 1
    fi
}

# Reset function - resets all modular components
reset_kiosk() {
    log "Resetting modular kiosk configuration"

    local modules=(
        "40-browser.sh"
        "20-compositor.sh" 
        "30-app.sh"
    )

    for module in "${modules[@]}"; do
        local module_path="$SCRIPT_DIR/$module"
        
        if [[ -f "$module_path" ]]; then
            log "Resetting module: $module"
            chmod +x "$module_path"
            "$module_path" reset || log "Warning: Failed to reset $module"
        fi
    done

    # Reset boot target
    systemctl set-default multi-user.target
    
    log "Modular kiosk reset completed"
}

# Validation function - validates all components
validate_kiosk() {
    log "Validating modular kiosk configuration"

    local errors=0
    local modules=(
        "30-app.sh"
        "20-compositor.sh"
        "40-browser.sh"
    )

    for module in "${modules[@]}"; do
        local module_path="$SCRIPT_DIR/$module"
        
        if [[ -f "$module_path" ]]; then
            log "Validating module: $module"
            chmod +x "$module_path"
            
            if "$module_path" validate; then
                log "✅ Module $module validation passed"
            else
                log "❌ Module $module validation failed"
                ((errors++))
            fi
        else
            log "❌ Module $module not found"
            ((errors++))
        fi
    done

    # Check if default target is graphical
    if ! systemctl get-default | grep -q "graphical.target"; then
        log "⚠️  Default target is not graphical.target"
    fi

    if [[ $errors -eq 0 ]]; then
        log "✅ Modular kiosk validation passed"
        return 0
    else
        log "❌ Modular kiosk validation failed with $errors errors"
        return 1
    fi
}

# Command line interface
case "${1:-setup}" in
    "setup")
        setup_kiosk
        ;;
    "reset")
        reset_kiosk
        ;;
    "validate")
        validate_kiosk
        ;;
    *)
        echo "Usage: $0 {setup|reset|validate}"
        echo "This module orchestrates the modular kiosk architecture:"
        echo "  - Vue.js app (30-app.sh)"
        echo "  - Sway compositor (20-compositor.sh)" 
        echo "  - Chromium browser (40-browser.sh)"
        exit 1
        ;;
esac