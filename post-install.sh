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

# --- Auto-login on TTY1 ---
log "Setting up auto-login for $USER"
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM
EOF
systemctl daemon-reexec

# --- Hyprland autostart ---
log "Setting up Hyprland configuration"
mkdir -p $HOME_DIR/.config/hypr
mkdir -p $HOME_DIR/.config/systemd/user

cat > $HOME_DIR/.config/hypr/hyprland.conf <<EOF
# Basic Hyprland configuration
monitor=,preferred,auto,1

# Input configuration
input {
    kb_layout = us
    follow_mouse = 1
}

# General configuration
general {
    gaps_in = 5
    gaps_out = 20
    border_size = 2
    col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
    col.inactive_border = rgba(595959aa)
    layout = dwindle
}

# Window rules for fullscreen applications
windowrulev2 = fullscreen,class:^(chromium)$

# Key bindings
bind = SUPER, Q, killactive
bind = SUPER, M, exit
bind = SUPER, V, togglefloating
bind = SUPER, P, pseudo
bind = SUPER, J, togglesplit
bind = SUPER, Return, exec, foot
bind = SUPER, T, exec, foot
bind = SUPER, E, exec, thunar

# Move focus with mainMod + arrow keys
bind = SUPER, left, movefocus, l
bind = SUPER, right, movefocus, r
bind = SUPER, up, movefocus, u
bind = SUPER, down, movefocus, d

# Switch workspaces with mainMod + [0-9]
bind = SUPER, 1, workspace, 1
bind = SUPER, 2, workspace, 2
bind = SUPER, 3, workspace, 3
bind = SUPER, 4, workspace, 4
bind = SUPER, 5, workspace, 5

# Move active window to a workspace with mainMod + SHIFT + [0-9]
bind = SUPER SHIFT, 1, movetoworkspace, 1
bind = SUPER SHIFT, 2, movetoworkspace, 2
bind = SUPER SHIFT, 3, movetoworkspace, 3

# Mouse bindings
bindm = SUPER, mouse:272, movewindow
bindm = SUPER, mouse:273, resizewindow
EOF

cat > $HOME_DIR/.config/systemd/user/hyprland.service <<EOF
[Unit]
Description=Hyprland Session
After=graphical.target

[Service]
ExecStart=/usr/bin/Hyprland
Restart=no
Environment=DISPLAY=:0

[Install]
WantedBy=default.target
EOF

chown -R $USER:$USER $HOME_DIR/.config
loginctl enable-linger $USER

# Create first-login script to enable user services after login
cat > $HOME_DIR/.config/first-login.sh <<'FIRSTLOGIN'
#!/bin/bash
# Enable and start Hyprland user service on first login only
if [ ! -f ~/.hyprland-enabled ]; then
    systemctl --user enable hyprland.service 2>/dev/null || true
    systemctl --user start hyprland.service 2>/dev/null || true
    touch ~/.hyprland-enabled
fi
FIRSTLOGIN

chmod +x $HOME_DIR/.config/first-login.sh

# Add to user's shell profile to run on first login
cat >> $HOME_DIR/.profile <<'PROFILE'
# Run first-login setup if it exists
if [ -f ~/.config/first-login.sh ]; then
    ~/.config/first-login.sh
    rm -f ~/.config/first-login.sh
fi
PROFILE

chown $USER:$USER $HOME_DIR/.profile $HOME_DIR/.config/first-login.sh

# --- Plymouth splash (Route 19 logo) ---
log "Setting up Plymouth splash theme"
THEME_DIR=/usr/share/plymouth/themes/route19
mkdir -p $THEME_DIR

# Copy logo from local assets
if [ -f /root/assets/route19-logo.png ]; then
    cp /root/assets/route19-logo.png $THEME_DIR/logo.png
    log "Plymouth logo copied from assets"
else
    log "WARNING: Logo asset not found, creating fallback"
    # Create a simple text fallback
    echo "Route 19" > $THEME_DIR/logo.png
fi

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
log "Plymouth theme configured"

# --- Cleanup ---
log "Cleaning up post-install files"
systemctl disable post-install.service
rm -f /root/post-install.sh
rm -rf /root/assets

log "==> Post-install tasks complete. The system will auto-login $USER and launch Hyprland with Plymouth splash."
