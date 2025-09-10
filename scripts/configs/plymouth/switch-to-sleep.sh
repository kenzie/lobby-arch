#!/usr/bin/env bash
# Switch Plymouth to sleep theme for maintenance window
set -euo pipefail

# Set sleep theme
plymouth-set-default-theme route19-sleep 2>/dev/null || {
    echo "WARNING: Failed to set Plymouth sleep theme"
    exit 1
}

# Show Plymouth with sleep theme
plymouth --show-splash 2>/dev/null || {
    echo "WARNING: Failed to show Plymouth splash"
    exit 1
}

# Wait for Plymouth to be ready
while ! plymouth --ping 2>/dev/null; do
    sleep 0.1
done

echo "Plymouth sleep theme activated"