#!/usr/bin/env bash
# Tailscale configuration script for chroot environment

set -euo pipefail

TAILSCALE_AUTH_KEY="${1:-}"

echo "==> Configuring Tailscale..."

# Enable tailscaled service
systemctl enable tailscaled

# Configure security hardening
cat > /etc/sysctl.d/99-tailscale-hardening.conf <<EOF
# Tailscale security hardening
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.rp_filter = 1
EOF

# Configure Tailscale if auth key provided
if [[ -n "${TAILSCALE_AUTH_KEY}" ]]; then
    echo "==> Starting tailscaled and connecting with auth key..."

    # Start tailscaled temporarily to configure
    systemctl start tailscaled
    sleep 3

    # Connect with auth key
    if tailscale up --auth-key="${TAILSCALE_AUTH_KEY}" --ssh --accept-routes; then
        echo "✓ Tailscale configured successfully with provided auth key"
    else
        echo "✗ Failed to configure Tailscale with auth key"
        echo "Tailscale installed but not configured - run 'sudo tailscale up --ssh --accept-routes' after reboot"
    fi
else
    echo "✓ Tailscale installed but not configured (no auth key provided)"
    echo "Run 'sudo tailscale up --ssh --accept-routes' after reboot to connect"
fi