#!/bin/bash
# Lobby Browser Wrapper
# In a kiosk, browser should only exit when systemd stops it

# Handle systemd stop signals properly
trap 'exit 0' SIGTERM SIGINT

exec /usr/bin/chromium \
    --no-sandbox \
    --disable-dev-shm-usage \
    --ozone-platform=wayland \
    --disable-extensions \
    --disable-plugins \
    --no-first-run \
    --no-default-browser-check \
    --kiosk http://localhost:8080 "$@"

# If we reach here, browser exited unexpectedly (not via systemd stop)
exit 1