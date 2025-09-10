#!/usr/bin/env bash
# Plymouth Boot Splash Configuration Module

set -euo pipefail

# Module info
MODULE_NAME="Plymouth Setup"
MODULE_VERSION="1.0"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../configs"

# Default values
USER="${LOBBY_USER:-lobby}"
HOME_DIR="${LOBBY_HOME:-/home/$USER}"
THEME_DIR="/usr/share/plymouth/themes/route19"
SLEEP_THEME_DIR="/usr/share/plymouth/themes/route19-sleep"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODULE_NAME] $1" | tee -a "${LOBBY_LOG:-/var/log/lobby-setup.log}"
}

# Main setup function
setup_plymouth() {
    log "Setting up Plymouth splash theme"
    
    # Create theme directories
    mkdir -p "$THEME_DIR"
    mkdir -p "$SLEEP_THEME_DIR"
    
    # Copy and process Plymouth theme files
    sed "s|{{THEME_DIR}}|$THEME_DIR|g" "$CONFIG_DIR/plymouth/route19.plymouth" > "$THEME_DIR/route19.plymouth"
    cp "$CONFIG_DIR/plymouth/route19.script" "$THEME_DIR/route19.script"
    
    # Copy and process sleep theme files
    sed "s|{{THEME_DIR}}|$SLEEP_THEME_DIR|g" "$CONFIG_DIR/plymouth/route19-sleep.plymouth" > "$SLEEP_THEME_DIR/route19-sleep.plymouth"
    cp "$CONFIG_DIR/plymouth/route19-sleep.script" "$SLEEP_THEME_DIR/route19-sleep.script"
    
    # Logo will be handled by Plymouth only (no desktop wallpaper needed for kiosk)
    
    # Copy logo for both Plymouth themes
    if [ -f "$CONFIG_DIR/plymouth/logo.png" ]; then
        cp "$CONFIG_DIR/plymouth/logo.png" "$THEME_DIR/logo.png"
        cp "$CONFIG_DIR/plymouth/logo.png" "$SLEEP_THEME_DIR/logo.png"
        log "Plymouth logo copied from config directory"
    elif [ -f "$SCRIPT_DIR/../../assets/route19-logo.png" ]; then
        cp "$SCRIPT_DIR/../../assets/route19-logo.png" "$THEME_DIR/logo.png"
        cp "$SCRIPT_DIR/../../assets/route19-logo.png" "$SLEEP_THEME_DIR/logo.png"
        log "Plymouth logo copied from assets"
    elif [ -f /root/assets/route19-logo.png ]; then
        cp /root/assets/route19-logo.png "$THEME_DIR/logo.png"
        cp /root/assets/route19-logo.png "$SLEEP_THEME_DIR/logo.png"
        log "Plymouth logo copied from /root/assets"
    else
        log "WARNING: Logo asset not found, creating fallback"
        echo "Route 19" > "$THEME_DIR/logo.png"
        echo "Route 19" > "$SLEEP_THEME_DIR/logo.png"
    fi
    
    # Configure mkinitcpio hooks for Plymouth
    log "Configuring mkinitcpio hooks for Plymouth"
    if ! grep -q "plymouth" /etc/mkinitcpio.conf; then
        # Backup original configuration
        cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.backup
        
        # Add plymouth hook before filesystems
        sed -i 's/HOOKS=(\([^)]*\) filesystems/HOOKS=(\1 plymouth filesystems/' /etc/mkinitcpio.conf
        log "Added Plymouth hook to mkinitcpio configuration"
        
        # Regenerate initramfs
        log "Regenerating initramfs with Plymouth support"
        mkinitcpio -p linux || {
            log "WARNING: Failed to regenerate initramfs (may not be in chroot environment)"
        }
    else
        log "Plymouth hook already present in mkinitcpio configuration"
    fi
    
    # Set Plymouth theme
    plymouth-set-default-theme -R route19 2>/dev/null || {
        log "WARNING: Failed to set Plymouth theme (may not be in chroot environment)"
    }
    
    # Mask default plymouth-quit to prevent early termination
    log "Configuring Plymouth to stay active until kiosk launches"
    systemctl mask plymouth-quit.service || true
    
    
    
    # Configure Plymouth for shutdown/reboot
    log "Configuring Plymouth for shutdown and reboot"
    
    # Create plymouth shutdown configuration
    cat > /etc/systemd/system/plymouth-poweroff.service <<EOF
[Unit]
Description=Show Plymouth Boot Screen on Shutdown
DefaultDependencies=false
Before=poweroff.target reboot.target halt.target
Conflicts=emergency.service emergency.target rescue.service rescue.target

[Service]
Type=forking
ExecStart=/usr/bin/plymouth --show-splash
ExecStartPost=/bin/bash -c 'while ! plymouth --ping; do sleep 0.1; done'
RemainAfterExit=yes
TimeoutStartSec=30

[Install]
WantedBy=poweroff.target reboot.target halt.target
EOF

    # Enable the shutdown service
    systemctl enable plymouth-poweroff.service
    
    # Ensure Plymouth shows during shutdown/reboot by configuring kernel params
    if [[ -f /etc/default/grub ]]; then
        if ! grep -q "splash quiet" /etc/default/grub; then
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 splash quiet"/' /etc/default/grub
            grub-mkconfig -o /boot/grub/grub.cfg
        fi
    else
        log "GRUB not found, assuming systemd-boot - kernel params should already include splash"
    fi
    
        

        # This service waits for the Hyprland process and Chromium to be running, then quits Plymouth.
    log "Creating kiosk-aware plymouth-quit-wait service"
    cat > /etc/systemd/system/plymouth-quit-wait.service <<EOF
[Unit]
Description=Hold until boot process finishes up (Kiosk Version)
After=lobby-kiosk.service
Wants=lobby-kiosk.service
# Ensure we run after the kiosk service is actually active
Requisite=lobby-kiosk.service

[Service]
Type=oneshot
# Wait for both Hyprland and Chromium to be running (indicates kiosk is ready)
ExecStartPre=/bin/bash -c 'echo "Waiting for kiosk to be ready..."; for i in {1..120}; do if pgrep Hyprland >/dev/null && pgrep chromium >/dev/null; then echo "Kiosk ready after $i seconds"; break; fi; sleep 1; done'
# Give an extra moment for display to stabilize
ExecStartPre=/bin/bash -c 'sleep 3'
ExecStart=/usr/bin/plymouth quit
RemainAfterExit=yes
# Add timeout to prevent hanging
TimeoutStartSec=150
[Install]
WantedBy=graphical.target
EOF

    systemctl enable plymouth-quit-wait.service

    log "Plymouth theme configuration completed"
}

# Reset function
reset_plymouth() {
    log "Resetting Plymouth configuration"
    
    # Remove theme directories
    rm -rf "$THEME_DIR"
    rm -rf "$SLEEP_THEME_DIR"
    
    # Reset Plymouth services
    systemctl unmask plymouth-quit.service || true
    rm -f /etc/systemd/system/plymouth-quit-wait.service
    
    # Reset to default theme
    plymouth-set-default-theme -R text 2>/dev/null || true
    
    # Recreate configuration
    setup_plymouth
    
    log "Plymouth configuration reset completed"
}

# Validation function
validate_plymouth() {
    local errors=0
    
    # Check if theme directory exists
    if [[ ! -d "$THEME_DIR" ]]; then
        log "ERROR: Plymouth theme directory not found"
        ((errors++))
    fi
    
    # Check if theme files exist
    if [[ ! -f "$THEME_DIR/route19.plymouth" ]]; then
        log "ERROR: Plymouth theme file not found"
        ((errors++))
    fi
    
    if [[ ! -f "$THEME_DIR/route19.script" ]]; then
        log "ERROR: Plymouth script file not found"
        ((errors++))
    fi
    
    if [[ ! -f "$THEME_DIR/logo.png" ]]; then
        log "ERROR: Plymouth logo not found"
        ((errors++))
    fi
    
    # Note: Hyprland wallpaper check removed - system now uses X11 + Cage kiosk
    
    # Check current Plymouth theme
    local current_theme
    current_theme=$(plymouth-set-default-theme 2>/dev/null || echo "unknown")
    if [[ "$current_theme" != "route19" ]]; then
        log "WARNING: Plymouth theme not set to route19 (current: $current_theme)"
    fi
    
    # Check if Plymouth hook is in mkinitcpio configuration
    if ! grep -q "plymouth" /etc/mkinitcpio.conf; then
        log "ERROR: Plymouth hook not found in mkinitcpio configuration"
        ((errors++))
    fi
    
    # Check if custom Plymouth quit wait service exists
    if [[ ! -f "/etc/systemd/system/plymouth-quit-wait.service" ]]; then
        log "ERROR: Plymouth quit wait service not found"
        ((errors++))
    fi
    
    # Check if default Plymouth quit service is masked
    if ! systemctl is-masked plymouth-quit.service >/dev/null 2>&1; then
        log "WARNING: Default Plymouth quit service is not masked"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log "Plymouth validation passed"
        return 0
    else
        log "Plymouth validation failed with $errors errors"
        return 1
    fi
}

# Command line interface
case "${1:-setup}" in
    "setup")
        setup_plymouth
        ;;
    "reset")
        reset_plymouth
        ;;
    "validate")
        validate_plymouth
        ;;
    *)
        echo "Usage: $0 {setup|reset|validate}"
        exit 1
        ;;
esac