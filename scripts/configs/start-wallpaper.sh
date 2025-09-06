#!/bin/bash
# Route 19 wallpaper startup script
sleep 3
pkill swaybg 2>/dev/null

# Use absolute path and ensure the file exists
WALLPAPER_PATH="{{HOME_DIR}}/.config/hypr/route19-centered.png"
if [[ -f "$WALLPAPER_PATH" ]]; then
    swaybg -i "$WALLPAPER_PATH" -m center -c "#1a1a1a" &
else
    echo "Wallpaper file not found: $WALLPAPER_PATH" >&2
fi