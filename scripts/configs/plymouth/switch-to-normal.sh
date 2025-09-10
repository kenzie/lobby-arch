#!/usr/bin/env bash
# Switch Plymouth back to normal theme after maintenance
set -euo pipefail

# Quit current Plymouth
plymouth quit 2>/dev/null || true

# Set normal theme
plymouth-set-default-theme route19 2>/dev/null || {
    echo "WARNING: Failed to set Plymouth normal theme"
    exit 1
}

echo "Plymouth normal theme restored"