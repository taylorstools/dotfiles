#!/usr/bin/env bash

set -uo pipefail

mkdir -p "$HOME/.dotfiles/Wallpapers"
EFFECTSWALLPAPEROUTPUT="$HOME/.config/.EffectsWallpaper.png"
STATE="/tmp/qs-current-wallpaper"

while true; do
    WALLPAPER="$(qs ipc call wallpaper get 2>/dev/null | tail -n 1)" || WALLPAPER=""

    # Anything that isn't an image file on disk ("Target not found." while the
    # shell starts, an ERROR string in per-monitor mode, a #colour wallpaper)
    if [[ ! -f "$WALLPAPER" ]]; then
        sleep 1
        continue
    fi

    # Wallpaper unchanged and effects wallpaper exists
    if [[ -f "$STATE" && "$(cat "$STATE")" == "$WALLPAPER" && -f "$EFFECTSWALLPAPEROUTPUT" ]]; then
        sleep 1
        continue
    fi

    echo "New wallpaper detected: $WALLPAPER"

    # Create wallpaper for hyprlock and wlogout; state is recorded only on success
    if ! magick "$WALLPAPER" -fill black -colorize 70% -blur 0x15 "$EFFECTSWALLPAPEROUTPUT"; then
        echo "magick failed on $WALLPAPER, retrying in 5s" >&2
        sleep 5
        continue
    fi
    echo "$WALLPAPER" > "$STATE"

    # Set effects wallpaper as swaybg background (used in overview).
    # Via the helper, which replaces the running swaybg instead of adding
    # another one to the pile.
    "$HOME/scripts/niri_set-wallpaper.sh" "$EFFECTSWALLPAPEROUTPUT" || true

    # Recolour the wlogout icons
    "$HOME/scripts/wlogout_make-icons.sh" || echo "wlogout_make-icons.sh failed" >&2
done
