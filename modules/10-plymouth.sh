#!/usr/bin/env bash
# Lobby Plymouth Module (Boot Themes)

set -euo pipefail

# Module info
MODULE_NAME="Lobby Plymouth Setup (Boot Themes)"
MODULE_VERSION="1.0"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODULE_NAME] $1" | tee -a "${LOBBY_LOG:-/var/log/lobby-setup.log}"
}

# Main setup function
setup_plymouth() {
    log "Setting up Plymouth boot themes for lobby kiosk"

    # --- 1. Install Plymouth ---
    log "Installing Plymouth and dependencies"
    pacman -S --noconfirm --needed plymouth || {
        log "ERROR: Failed to install Plymouth"
        return 1
    }

    # --- 2. Create Route 19 Theme Directory ---
    local theme_dir="/usr/share/plymouth/themes/route19"
    log "Creating Route 19 Plymouth theme at $theme_dir"
    mkdir -p "$theme_dir"

    # --- 3. Create Theme Files ---
    log "Installing Route 19 theme files"
    
    # Theme configuration
    cat > "$theme_dir/route19.plymouth" <<'EOF'
[Plymouth Theme]
Name=Route 19
Description=Route 19 Logo Boot Theme
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/route19
ScriptFile=/usr/share/plymouth/themes/route19/route19.script
EOF

    # Theme script
    cat > "$theme_dir/route19.script" <<'EOF'
# Route 19 Plymouth Theme Script
# Clean, professional boot screen with logo

# Set background color (dark blue/slate)
Window.SetBackgroundTopColor(0.059, 0.090, 0.161);  # #0f172a
Window.SetBackgroundBottomColor(0.059, 0.090, 0.161);

# Load and display logo if available
logo.image = Image("logo.png");
if (logo.image) {
    logo.sprite = Sprite(logo.image);
    logo.sprite.SetPosition(Window.GetWidth()/2 - logo.image.GetWidth()/2, 
                           Window.GetHeight()/2 - logo.image.GetHeight()/2 - 50);
}

# Progress indicator
progress_box.image = Image.Text("Loading...", 1, 1, 1);
progress_box.sprite = Sprite(progress_box.image);
progress_box.sprite.SetPosition(Window.GetWidth()/2 - progress_box.image.GetWidth()/2,
                               Window.GetHeight()/2 + 50);

# Boot progress callback
Plymouth.SetBootProgressFunction(boot_progress);

fun boot_progress(duration, progress) {
    if (progress_box.sprite) {
        progress_box.sprite.SetOpacity(1);
    }
}

# Message display
message_sprite = Sprite();
message_sprite.SetPosition(Window.GetWidth()/2, Window.GetHeight() * 0.8, 10000);

fun display_normal_callback() {
    global.status = "normal";
}

fun display_password_callback(prompt, bullets) {
    global.status = "password";
    message_sprite.SetImage(Image.Text(prompt, 1, 1, 1));
}

fun display_question_callback(prompt, entry) {
    global.status = "question";
    message_sprite.SetImage(Image.Text(prompt, 1, 1, 1));
}

fun display_message_callback(message) {
    message_sprite.SetImage(Image.Text(message, 1, 1, 1));
}

Plymouth.SetDisplayNormalFunction(display_normal_callback);
Plymouth.SetDisplayPasswordFunction(display_password_callback);
Plymouth.SetDisplayQuestionFunction(display_question_callback);
Plymouth.SetDisplayMessageFunction(display_message_callback);
EOF

    # Create placeholder logo (1x1 transparent PNG if no logo provided)
    if [[ ! -f "$theme_dir/logo.png" ]]; then
        log "Creating placeholder logo (replace with actual Route 19 logo)"
        # Create minimal transparent PNG placeholder
        echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVQYV2NgAAIAAAUAAarVyFEAAAAASUVORK5CYII=" | base64 -d > "$theme_dir/logo.png"
    fi

    # --- 4. Configure Plymouth in Boot ---
    log "Configuring Plymouth in initramfs"
    
    # Add Plymouth hook to mkinitcpio
    local mkinitcpio_conf="/etc/mkinitcpio.conf"
    if ! grep -q "plymouth" "$mkinitcpio_conf"; then
        log "Adding Plymouth to mkinitcpio hooks"
        sed -i 's/^HOOKS=(/&plymouth /' "$mkinitcpio_conf"
    fi

    # Set default theme
    log "Setting Route 19 as default Plymouth theme"
    plymouth-set-default-theme route19 || {
        log "WARNING: Failed to set Plymouth theme (may need manual setup)"
    }

    # --- 5. Update Kernel Parameters ---
    log "Configuring kernel parameters for Plymouth"
    local grub_config="/etc/default/grub"
    
    if [[ -f "$grub_config" ]]; then
        # Add quiet splash to GRUB_CMDLINE_LINUX_DEFAULT if not present
        if ! grep -q "quiet splash" "$grub_config"; then
            log "Adding quiet splash to GRUB configuration"
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*"/&quiet splash/' "$grub_config"
            sed -i 's/""quiet splash/"quiet splash/' "$grub_config"
        fi
        
        log "GRUB configuration updated. Run 'grub-mkconfig -o /boot/grub/grub.cfg' and 'mkinitcpio -P' to apply"
    else
        log "WARNING: GRUB configuration not found. Manual kernel parameter setup required"
    fi

    log "Plymouth boot theme setup completed"
}

# Reset function
reset_plymouth() {
    log "Resetting Plymouth configuration"

    # Remove theme directory
    rm -rf /usr/share/plymouth/themes/route19

    # Reset to default theme
    plymouth-set-default-theme spinfinity 2>/dev/null || true

    # Remove Plymouth from mkinitcpio hooks
    local mkinitcpio_conf="/etc/mkinitcpio.conf"
    if [[ -f "$mkinitcpio_conf" ]]; then
        sed -i 's/plymouth //g' "$mkinitcpio_conf"
    fi

    log "Plymouth reset completed"
}

# Validation function
validate_plymouth() {
    local errors=0

    # Check if Plymouth is installed
    if ! command -v plymouth >/dev/null; then
        log "ERROR: Plymouth not installed"
        ((errors++))
    fi

    # Check if theme exists
    if [[ ! -d /usr/share/plymouth/themes/route19 ]]; then
        log "ERROR: Route 19 theme not found"
        ((errors++))
    fi

    # Check theme files
    if [[ ! -f /usr/share/plymouth/themes/route19/route19.plymouth ]]; then
        log "ERROR: Route 19 theme configuration missing"
        ((errors++))
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