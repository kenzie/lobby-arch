#!/usr/bin/env bash
# Lobby App Module (Vue.js lobby-display)

set -euo pipefail

# Module info
MODULE_NAME="Lobby App Setup (Vue.js)"
MODULE_VERSION="1.0"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
USER="${LOBBY_USER:-lobby}"
HOME_DIR="${LOBBY_HOME:-/home/$USER}"
LOBBY_DISPLAY_DIR="/opt/lobby-display"
LOBBY_DISPLAY_URL="https://github.com/kenzie/lobby-display.git"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODULE_NAME] $1" | tee -a "${LOBBY_LOG:-/var/log/lobby-setup.log}"
}

# Main setup function
setup_app() {
    log "Setting up Vue.js lobby-display application"
    
    # Stop app service for clean setup
    log "Stopping app service"
    systemctl stop lobby-app.service 2>/dev/null || true

    # --- 1. Install Node.js and NPM ---
    log "Installing Node.js and NPM"
    pacman -S --noconfirm --needed nodejs npm || {
        log "ERROR: Failed to install Node.js/NPM"
        return 1
    }

    # --- 2. Clone and Build Vue.js App ---
    log "Cloning lobby-display repository"
    if [[ -d "$LOBBY_DISPLAY_DIR" ]]; then
        log "Lobby display directory exists, pulling latest"
        cd "$LOBBY_DISPLAY_DIR"
        git pull
    else
        git clone "$LOBBY_DISPLAY_URL" "$LOBBY_DISPLAY_DIR"
    fi
    chown -R "$USER:$USER" "$LOBBY_DISPLAY_DIR"

    log "Installing lobby-display dependencies"
    cd "$LOBBY_DISPLAY_DIR"
    sudo -u "$USER" npm install || { 
        log "ERROR: npm install failed"
        return 1
    }
    
    log "Building lobby-display application"
    sudo -u "$USER" npm run build || { 
        log "ERROR: npm run build failed"
        return 1
    }
    log "lobby-display build completed successfully"

    # --- 3. Create App Service ---
    log "Creating Vue.js app systemd service"
    cat > /etc/systemd/system/lobby-app.service <<'EOF'
[Unit]
Description=Lobby Display Vue.js App
After=network.target
Wants=network.target

[Service]
Type=simple
User=lobby
WorkingDirectory=/opt/lobby-display
ExecStart=/usr/bin/npm run preview -- --port 8080 --host
Restart=on-failure
RestartSec=10
StartLimitIntervalSec=60
StartLimitBurst=5

# Resource limits
MemoryMax=512M
MemoryAccounting=yes

# Security
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/lobby-display
PrivateTmp=true

# Logging
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # --- 4. Enable Service ---
    log "Enabling Vue.js app service"
    systemctl daemon-reload
    systemctl enable lobby-app.service

    log "Vue.js lobby-display app setup completed successfully"
}

# Reset function
reset_app() {
    log "Resetting Vue.js app configuration"

    # Stop and disable service
    systemctl stop lobby-app.service || true
    systemctl disable lobby-app.service || true

    # Remove service file
    rm -f /etc/systemd/system/lobby-app.service

    # Remove app directory
    rm -rf "$LOBBY_DISPLAY_DIR"

    systemctl daemon-reload
    log "Vue.js app reset completed"
}

# Validation function
validate_app() {
    local errors=0

    # Check if service file exists
    if [[ ! -f /etc/systemd/system/lobby-app.service ]]; then
        log "ERROR: App service not found"
        ((errors++))
    fi

    # Check if app directory exists
    if [[ ! -d "$LOBBY_DISPLAY_DIR" ]]; then
        log "ERROR: App directory not found"
        ((errors++))
    fi

    # Check if built files exist
    if [[ ! -d "$LOBBY_DISPLAY_DIR/dist" ]]; then
        log "ERROR: App not built (dist directory missing)"
        ((errors++))
    fi

    # Check Node.js and NPM
    if ! command -v node >/dev/null; then log "ERROR: Node.js not installed"; ((errors++)); fi
    if ! command -v npm >/dev/null; then log "ERROR: NPM not installed"; ((errors++)); fi

    if [[ $errors -eq 0 ]]; then
        log "App validation passed"
        return 0
    else
        log "App validation failed with $errors errors"
        return 1
    fi
}

# Update function - for refreshing app from git
update_app() {
    log "Updating lobby-display app from git repository"
    
    if [[ ! -d "$LOBBY_DISPLAY_DIR" ]]; then
        log "ERROR: App directory not found. Run setup first."
        return 1
    fi

    cd "$LOBBY_DISPLAY_DIR"
    
    # Pull latest changes
    log "Pulling latest changes"
    git pull || {
        log "ERROR: Git pull failed"
        return 1
    }

    # Install dependencies (in case package.json changed)
    log "Installing dependencies"
    sudo -u "$USER" npm install || {
        log "ERROR: npm install failed"
        return 1
    }

    # Rebuild application
    log "Rebuilding application"
    sudo -u "$USER" npm run build || {
        log "ERROR: npm run build failed"
        return 1
    }

    # Restart service to use new build
    log "Restarting app service"
    systemctl restart lobby-app.service

    log "App update completed successfully"
}

# Command line interface
case "${1:-setup}" in
    "setup")
        setup_app
        ;;
    "reset")
        reset_app
        ;;
    "validate")
        validate_app
        ;;
    "update")
        update_app
        ;;
    *)
        echo "Usage: $0 {setup|reset|validate|update}"
        exit 1
        ;;
esac