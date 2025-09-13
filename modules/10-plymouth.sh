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
# Unified theme - no separate sleep theme needed

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODULE_NAME] $1" | tee -a "${LOBBY_LOG:-/var/log/lobby-setup.log}"
}

# Main setup function
setup_plymouth() {
    log "Setting up Plymouth splash theme"
    
    # Create theme directory
    mkdir -p "$THEME_DIR"
    
    # Copy and process unified Plymouth theme files
    sed "s|{{THEME_DIR}}|$THEME_DIR|g" "$CONFIG_DIR/plymouth/route19.plymouth" > "$THEME_DIR/route19.plymouth"
    cp "$CONFIG_DIR/plymouth/route19.script" "$THEME_DIR/route19.script"
    
    # Logo will be handled by Plymouth only (no desktop wallpaper needed for kiosk)
    
    # Copy logo for Plymouth theme
    if [ -f "$CONFIG_DIR/plymouth/logo.png" ]; then
        cp "$CONFIG_DIR/plymouth/logo.png" "$THEME_DIR/logo.png"
        log "Plymouth logo copied from config directory"
    elif [ -f "$SCRIPT_DIR/../../assets/route19-logo.png" ]; then
        cp "$SCRIPT_DIR/../../assets/route19-logo.png" "$THEME_DIR/logo.png"
        log "Plymouth logo copied from assets"
    elif [ -f /root/assets/route19-logo.png ]; then
        cp /root/assets/route19-logo.png "$THEME_DIR/logo.png"
        log "Plymouth logo copied from /root/assets"
    else
        log "WARNING: Logo asset not found, creating fallback"
        echo "Route 19" > "$THEME_DIR/logo.png"
    fi
    
    # Configure mkinitcpio hooks for Plymouth (Arch best practices)
    log "Configuring mkinitcpio hooks and modules for Plymouth"
    if ! grep -q "systemd plymouth" /etc/mkinitcpio.conf; then
        # Backup original configuration
        cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.backup
        
        # AMD graphics will load automatically - remove any explicit module loading
        sed -i 's/^MODULES=(amdgpu)/MODULES=()/' /etc/mkinitcpio.conf
        sed -i 's/^MODULES=()/MODULES=()/' /etc/mkinitcpio.conf
        
        # Configure hooks in proper order: systemd must precede plymouth
        sed -i 's/^HOOKS=.*/HOOKS=(systemd plymouth autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)/' /etc/mkinitcpio.conf
        log "Configured mkinitcpio with automatic graphics detection and proper hook order"
        
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

    # Enable built-in Plymouth services for shutdown/reboot by creating symlinks
    mkdir -p /etc/systemd/system/reboot.target.wants
    mkdir -p /etc/systemd/system/poweroff.target.wants
    ln -sf /usr/lib/systemd/system/plymouth-reboot.service /etc/systemd/system/reboot.target.wants/
    ln -sf /usr/lib/systemd/system/plymouth-poweroff.service /etc/systemd/system/poweroff.target.wants/
    systemctl daemon-reload
    
    # Ensure Plymouth shows during shutdown/reboot by configuring kernel params
    if [[ -f /etc/default/grub ]]; then
        if ! grep -q "splash quiet" /etc/default/grub; then
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 splash quiet loglevel=0 rd.udev.log_level=0 rd.systemd.show_status=false systemd.show_status=false fbcon=nodefer vt.global_cursor_default=0 console=tty2"/' /etc/default/grub
            grub-mkconfig -o /boot/grub/grub.cfg
        fi
    else
        log "GRUB not found, configuring systemd-boot kernel parameters"
        # Update systemd-boot configuration
        BOOT_ENTRY="/boot/loader/entries/arch.conf"
        if [[ -f "$BOOT_ENTRY" ]]; then
            # Extract current root UUID and preserve it
            ROOT_UUID=$(grep "^options" "$BOOT_ENTRY" | grep -o "root=UUID=[^ ]*" || echo "root=LABEL=arch")
            # Update with enhanced kernel parameters for clean kiosk boot
            sed -i "s|^options.*|options $ROOT_UUID rw quiet splash tsc=unstable|" "$BOOT_ENTRY"
            log "Updated systemd-boot configuration with clean boot parameters"
        else
            log "WARNING: systemd-boot configuration not found at $BOOT_ENTRY"
        fi
    fi
    
        

        # This service waits for the Hyprland process and Chromium to be running, then quits Plymouth.
    log "Creating kiosk-aware plymouth-quit-wait service"
    cat > /etc/systemd/system/plymouth-quit-wait.service <<EOF
[Unit]
Description=Hold until boot process finishes up (Kiosk Version)

# Removed Requisite to prevent dependency failures - Wants is sufficient

[Service]
Type=oneshot
# Wait for Hyprland to be running (optimized for speed)
ExecStartPre=/bin/bash -c 'echo "Waiting for kiosk to be ready..."; for i in \$(seq 1 30); do if pgrep -f "chromium.*kiosk" >/dev/null; then echo "Kiosk fully ready after \$i seconds"; break; elif pgrep Hyprland >/dev/null; then echo "Hyprland ready, waiting for Chromium..."; fi; sleep 0.5; done'
ExecStart=/bin/bash -c "/usr/bin/plymouth quit --retain-splash || echo \"Plymouth quit complete\"; sleep 0.5"
RemainAfterExit=yes
# Add timeout to prevent hanging
TimeoutStartSec=40
[Install]
WantedBy=graphical.target
EOF

    systemctl enable plymouth-quit-wait.service

    log "Plymouth theme configuration completed"
}

# Reset function
reset_plymouth() {
    log "Resetting Plymouth configuration"
    
    # Remove theme directory
    rm -rf "$THEME_DIR"
    
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
    if ! systemctl list-unit-files plymouth-quit.service 2>/dev/null | grep -q "masked"; then
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