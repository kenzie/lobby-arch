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

cat > $HOME_DIR/.config/hypr/hyprland.conf <<EOF
monitor=HDMI-A-1,1920x1080@60
EOF

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

# --- Plymouth splash (Route 19 logo) ---
THEME_DIR=/usr/share/plymouth/themes/route19
mkdir -p $THEME_DIR
curl -sSL https://www.route19.com/assets/images/image01.png?v=fa76ddff -o $THEME_DIR/logo.png

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

plymouth-set-default-theme -R route19

# --- Cleanup ---
systemctl disable post-install.service
rm -f /tmp/post-install.sh

echo "==> Post-install tasks complete. The system will auto-login $USER and launch Hyprland with Plymouth splash."
