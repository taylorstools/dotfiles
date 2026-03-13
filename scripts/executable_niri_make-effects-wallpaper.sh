#!/usr/bin/env bash

set -euo pipefail

mkdir -p "$HOME/Wallpapers"
EFFECTSWALLPAPEROUTPUT="$HOME/.config/.EffectsWallpaper.png"
STATE="/tmp/dms-current-wallpaper"

while true; do
    if ! WALLPAPER="$(dms ipc call wallpaper get 2>/dev/null)"; then
        sleep 1
        continue
    fi

    # If wallpaper not changed and effects wallpaper exists, do nothing
    if [[ -z "$WALLPAPER" ]] || {
        [[ -f "$STATE" ]] &&
        [[ "$(cat "$STATE")" == "$WALLPAPER" ]] &&
        [[ -f "$EFFECTSWALLPAPEROUTPUT" ]]
    }; then
        echo "No wallpaper change."
        sleep 1
        continue
    fi

    # Run magick if DMS has new wallpaper
    echo "New wallpaper detected."
    echo "$WALLPAPER" > "$STATE"

    # Create wallpaper for hyprlock and wlogout
    echo "Running magick on wallpaper."
    magick "$WALLPAPER" -fill black -colorize 70% -blur 0x15 "$EFFECTSWALLPAPEROUTPUT"

    # Set effects wallpaper as swaybg background (used in overview)
    swaybg -m fill -i "$EFFECTSWALLPAPEROUTPUT" >/dev/null 2>&1 &

    # Run script to change the wlogout icons
    $HOME/scripts/wlogout_make-icons.sh
done