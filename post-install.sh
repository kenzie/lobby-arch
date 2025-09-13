#!/usr/bin/env bash
set -euo pipefail

USER="lobby"
HOME_DIR="/home/$USER"
LOGFILE="/var/log/post-install.log"

# Get script directory  
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOBBY_SCRIPT="$SCRIPT_DIR/lobby.sh"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

log "==> Starting modular post-install tasks..."

# Check if user exists
if ! id "$USER" >/dev/null 2>&1; then
    log "ERROR: User $USER does not exist"
    exit 1
fi

# Wait for network connectivity (skip in chroot)
if [[ -z "${CHROOT_INSTALL:-}" ]]; then
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
else
    log "Skipping network check (chroot environment)"
fi

# Create local bin directory for lobby user
LOBBY_BIN_DIR="$HOME_DIR/.local/bin"
sudo -u "$USER" mkdir -p "$LOBBY_BIN_DIR"

# Create symlink to lobby.sh in user's local bin (remove existing if present)
LOBBY_SYMLINK="$LOBBY_BIN_DIR/lobby"
if [[ -L "$LOBBY_SYMLINK" ]] || [[ -f "$LOBBY_SYMLINK" ]]; then
    rm -f "$LOBBY_SYMLINK"
fi
sudo -u "$USER" ln -s "$LOBBY_SCRIPT" "$LOBBY_SYMLINK"
log "Created symlink: $LOBBY_SYMLINK -> $LOBBY_SCRIPT"

# Add lobby user's local bin to PATH in .bashrc if not already present
BASHRC="$HOME_DIR/.bashrc"
if [[ -f "$BASHRC" ]] && ! grep -q "\$HOME/.local/bin" "$BASHRC"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' | sudo -u "$USER" tee -a "$BASHRC" >/dev/null
    log "Added ~/.local/bin to PATH in .bashrc"
fi

# Set environment variables for lobby.sh
export LOBBY_USER="$USER"
export LOBBY_HOME="$HOME_DIR"
export LOBBY_LOG="$LOGFILE"

# Sync modules if needed and run full lobby setup
log "Running lobby setup (sync and configure all modules)"
if "$LOBBY_SYMLINK" sync --main && "$LOBBY_SYMLINK" setup; then
    log "SUCCESS: Lobby setup completed successfully"
else
    exit_code=$?
    log "ERROR: Lobby setup failed with exit code $exit_code"
    log "Check '$LOBBY_LOG' and run 'sudo lobby setup' to retry."
    exit 1
fi

# Disable this service since it's completed (skip in chroot)
if [[ -z "${CHROOT_INSTALL:-}" ]]; then
    log "Disabling post-install service"
    systemctl disable post-install.service 2>/dev/null || true
else
    log "Skipping service disable (chroot environment)"
fi

log "==> Post-install tasks complete. The system will boot directly to Cage kiosk with Plymouth splash."
log "==> Use 'sudo lobby help' for system management and 'sudo lobby health' for diagnostics."
