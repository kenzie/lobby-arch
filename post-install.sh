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

# Set black background to prevent default wallpapers
misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
    col.splash = rgba(000000ff)
}

# Wallpaper configuration with centered Route 19 logo
exec = /home/$USER/.config/hypr/start-wallpaper.sh

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
bind = SUPER, W, killactive
bind = SUPER, M, exit
bind = SUPER, V, togglefloating
bind = SUPER, P, pseudo
bind = SUPER, J, togglesplit
bind = SUPER, Return, exec, alacritty
bind = SUPER, T, exec, alacritty
bind = SUPER, B, exec, chromium

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

# Create wallpaper startup script
cat > $HOME_DIR/.config/hypr/start-wallpaper.sh <<WALLPAPER
#!/bin/bash
# Route 19 wallpaper startup script
sleep 3
pkill swaybg 2>/dev/null

# Use absolute path and ensure the file exists
WALLPAPER_PATH="$HOME_DIR/.config/hypr/route19-centered.png"
if [[ -f "\$WALLPAPER_PATH" ]]; then
    swaybg -i "\$WALLPAPER_PATH" -m center -c "#1a1a1a" &
else
    echo "Wallpaper file not found: \$WALLPAPER_PATH" >&2
fi
WALLPAPER

chmod +x $HOME_DIR/.config/hypr/start-wallpaper.sh

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

# hyprpaper config no longer needed since we're using swaybg

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

# Copy logo to user's Hyprland config directory for wallpaper
if [ -f /root/assets/route19-logo.png ]; then
    cp /root/assets/route19-logo.png $HOME_DIR/.config/hypr/route19-centered.png
    chown $USER:$USER $HOME_DIR/.config/hypr/route19-centered.png
    log "Route 19 logo copied for Hyprland wallpaper"
else
    log "WARNING: Logo asset not found"
fi

# Still set up Plymouth but it likely won't be visible
if [ -f /root/assets/route19-logo.png ]; then
    cp /root/assets/route19-logo.png $THEME_DIR/logo.png
    log "Plymouth logo copied from assets"
else
    log "WARNING: Logo asset not found, creating fallback"
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

# --- Automatic Pacman Updates ---
log "Setting up automatic pacman updates"

# Create the update script
cat > /usr/local/bin/pacman-auto-update.sh <<'UPDATESCRIPT'
#!/bin/bash

# Automatic Pacman Updates Script with Error Recovery
# Log file location
LOG_FILE="/var/log/pacman-auto-update.log"
MAX_LOG_SIZE=10485760  # 10MB in bytes

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to rotate log if too large
rotate_log() {
    if [[ -f "$LOG_FILE" && $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null) -gt $MAX_LOG_SIZE ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        log_message "Log rotated due to size limit"
    fi
}

# Function to clean up old logs (keep last 5 rotated logs)
cleanup_old_logs() {
    find /var/log -name "pacman-auto-update.log.*" -type f | sort -r | tail -n +6 | xargs -r rm
}

# Function to handle pacman lock
handle_pacman_lock() {
    local lock_file="/var/lib/pacman/db.lck"
    if [[ -f "$lock_file" ]]; then
        log_message "Pacman lock file detected, checking if pacman is running..."
        if ! pgrep -x pacman >/dev/null; then
            log_message "No pacman process found, removing stale lock file"
            rm -f "$lock_file"
        else
            log_message "Pacman is running, waiting for completion..."
            while [[ -f "$lock_file" ]]; do
                sleep 30
            done
        fi
    fi
}

# Function to check system health before update
pre_update_checks() {
    log_message "Performing pre-update system checks..."
    
    # Check available disk space (need at least 1GB free)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 1048576 ]]; then
        log_message "ERROR: Insufficient disk space for updates (less than 1GB free)"
        return 1
    fi
    
    # Check if network is available
    if ! ping -c 1 archlinux.org >/dev/null 2>&1; then
        log_message "ERROR: No network connectivity"
        return 1
    fi
    
    log_message "Pre-update checks passed"
    return 0
}

# Function to perform the update
perform_update() {
    log_message "Starting automatic system update..."
    
    # Sync package databases
    if ! pacman -Sy --noconfirm; then
        log_message "ERROR: Failed to sync package databases"
        return 1
    fi
    
    # Check for updates
    local updates=$(pacman -Qu | wc -l)
    if [[ $updates -eq 0 ]]; then
        log_message "No updates available"
        return 0
    fi
    
    log_message "Found $updates package(s) to update"
    
    # Perform the update
    if pacman -Su --noconfirm; then
        log_message "System update completed successfully ($updates packages updated)"
        
        # Clean package cache (keep last 3 versions)
        if paccache -r -k3; then
            log_message "Package cache cleaned"
        fi
        
        return 0
    else
        log_message "ERROR: System update failed"
        return 1
    fi
}

# Function to handle post-update tasks
post_update_tasks() {
    # Check if reboot is needed (kernel update)
    if [[ -f /usr/lib/modules/$(uname -r) ]]; then
        log_message "No reboot required"
    else
        log_message "WARNING: Reboot may be required due to kernel update"
        # Create a flag file for manual inspection
        touch /var/log/reboot-required
    fi
    
    # Update file database
    if command -v updatedb >/dev/null; then
        updatedb 2>/dev/null && log_message "File database updated"
    fi
}

# Main execution
main() {
    rotate_log
    cleanup_old_logs
    
    log_message "=== Automatic Update Session Started ==="
    
    # Perform pre-update checks
    if ! pre_update_checks; then
        log_message "Pre-update checks failed, aborting update"
        exit 1
    fi
    
    # Handle any existing pacman lock
    handle_pacman_lock
    
    # Attempt the update with retries
    local max_retries=3
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        if perform_update; then
            post_update_tasks
            log_message "=== Update Session Completed Successfully ==="
            exit 0
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                log_message "Update failed, retry $retry_count/$max_retries in 60 seconds..."
                sleep 60
            fi
        fi
    done
    
    log_message "=== Update Session Failed After $max_retries Attempts ==="
    exit 1
}

# Execute main function
main "$@"
UPDATESCRIPT

chmod +x /usr/local/bin/pacman-auto-update.sh

# Create systemd service for automatic updates
cat > /etc/systemd/system/pacman-auto-update.service <<'UPDATESERVICE'
[Unit]
Description=Automatic Pacman System Updates
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/pacman-auto-update.sh
StandardOutput=journal
StandardError=journal
TimeoutStartSec=3600

[Install]
WantedBy=multi-user.target
UPDATESERVICE

# Create systemd timer for weekly scheduling
cat > /etc/systemd/system/pacman-auto-update.timer <<'UPDATETIMER'
[Unit]
Description=Weekly Automatic Pacman Updates
Requires=pacman-auto-update.service

[Timer]
OnCalendar=weekly
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
UPDATETIMER

# Create logrotate configuration
cat > /etc/logrotate.d/pacman-auto-update <<'LOGROTATE'
/var/log/pacman-auto-update.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
LOGROTATE

# Enable and start the update timer
systemctl daemon-reload
systemctl enable pacman-auto-update.timer
systemctl start pacman-auto-update.timer

log "Automatic pacman updates configured - runs weekly with error recovery and log management"

# --- Cleanup ---
log "Cleaning up post-install files"
systemctl disable post-install.service
rm -f /root/post-install.sh
rm -rf /root/assets

log "==> Post-install tasks complete. The system will auto-login $USER and launch Hyprland with Plymouth splash."
log "==> Automatic updates are enabled and will run weekly."
