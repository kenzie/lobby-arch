#!/usr/bin/env bash
set -euo pipefail

USER="lobby"
HOME_DIR="/home/$USER"

echo "==> Running post-install tasks..."

# --- Create auto-login on TTY1 ---
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM
EOF

systemctl daemon-reexec

# --- Configure Hyprland autostart ---
mkdir -p $HOME_DIR/.config/hypr
mkdir -p $HOME_DIR/.config/systemd/user

# Minimal config for first boot
cat > $HOME_DIR/.config/hypr/hyprland.conf <<EOF
monitor=HDMI-A-1,1920x1080@60
exec=chromium
EOF

# Create systemd user service to start Hyprland
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

# Enable linger so user service runs on boot
loginctl enable-linger $USER
sudo -u $USER systemctl --user enable hyprland.service

echo "==> Post-install tasks complete. The system will auto-login $USER and launch Hyprland on next boot."

# Optionally disable this service after first run
systemctl disable post-install.service
rm -f /tmp/post-install.sh
