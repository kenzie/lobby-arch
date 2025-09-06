#!/usr/bin/env bash
set -euo pipefail

USER="lobby"
HOME_DIR="/home/$USER"

echo "==> Running post-install tasks..."

# --- Auto-login on TTY1 ---
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM
EOF
systemctl daemon-reexec

# --- Hyprland autostart ---
mkdir -p $HOME_DIR/.config/hypr
mkdir -p $HOME_DIR/.config/systemd/user

# Minimal Hyprland config
cat > $HOME_DIR/.config/hypr/hyprland.conf <<EOF
monitor=HDMI-A-1,1920x1080@60
EOF

# Systemd user service to start Hyprland
cat > $HOME_DIR/.config/systemd/user/hyprland.service <<EOF
[Unit]
Description=Hyprland Session
After=graphical.target

[Service]
ExecStart=/usr/bin/Hyprland
Restart=always
Environment=DISPLAY=:0

[Install]
WantedBy=default.target
EOF

chown -R $USER:$USER $HOME_DIR/.config
loginctl enable-linger $USER
sudo -u $USER systemctl --user enable hyprland.service

# --- Install Plymouth and configure Route 19 splash ---
echo "==> Installing Plymouth splash..."
pacman -Sy --noconfirm plymouth plymouth-theme-spinner cdrtools

THEME_DIR=/usr/share/plymouth/themes/route19
mkdir -p $THEME_DIR

# Download Route 19 logo
curl -sSL https://www.route19.com/assets/images/image01.png?v=fa76ddff -o $THEME_DIR/logo.png

# Create custom theme
cat > $THEME_DIR/route19.plymouth <<EOF
[Plymouth Theme]
Name=Route19
Description=Route 19 splash theme
ModuleName=script

[script]
ImageDir=$THEME_DIR
ScriptFile=$THEME_DIR/route19.script
EOF

cat > $THEME_DIR/route19.script <<'EOF'
plymouth_set_background_image("logo.png");
EOF

# Set as default theme and rebuild initramfs
plymouth-set-default-theme -R route19

# --- Final cleanup ---
echo "==> Post-install tasks complete. The system will auto-login $USER and launch Hyprland with Plymouth splash."
systemctl disable post-install.service
rm -f /tmp/post-install.sh
