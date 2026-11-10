#!/usr/bin/env bash

# Keeps ~/.config/.EffectsWallpaper.png (the app drawer background) in sync
# with the Plasma wallpaper. Runs for the whole session from autostart, so no
# failure may end the loop: no `set -e`, every step checks for itself.
set -uo pipefail

mkdir -p "$HOME/.dotfiles/Wallpapers"
EFFECTSWALLPAPEROUTPUT="$HOME/.config/.EffectsWallpaper.png"
# Written next to the output and renamed into place, so the drawer never
# reads a half-written file.
TMPOUTPUT="$HOME/.config/.EffectsWallpaper.tmp.png"
# Which wallpaper the effects image was made from. In the runtime dir, which
# is emptied every boot, so the first run after login always rebuilds it:
# /tmp survives reboots here, and an old marker there can keep a stale image.
STATE="${XDG_RUNTIME_DIR:-/tmp}/plasma-current-wallpaper"

gcd() {
    local a=$1 b=$2 t
    while (( b )); do
        t=$(( a % b ))
        a=$b
        b=$t
    done
    echo "$a"
}

current_wallpaper() {
    # The Image= of the desktop's org.kde.image wallpaper, not the slideshow's.
    awk -F= '
        /^\[/ { inimage = /\[Wallpaper\]\[org\.kde\.image\]\[General\]$/ }
        inimage && $1 == "Image" { sub(/^[^=]*=/, ""); sub(/^file:\/\//, ""); print; exit }
    ' "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null
}

# Prints the current screen's aspect ratio as W:H, or fails.
screen_aspect() {
    local w h g
    # kscreen-doctor colours its output; strip that, then take the first
    # output that has a current (*) mode. Disconnected or disabled outputs
    # come first sometimes and have none.
    read -r w h < <(
        kscreen-doctor -o 2>/dev/null \
            | sed 's/\x1b\[[0-9;]*m//g' \
            | awk '/Modes:/ && match($0, /([0-9]+)x([0-9]+)@[0-9.]+\*/, m) { print m[1], m[2]; exit }'
    ) || return 1
    [[ "$w" =~ ^[1-9][0-9]*$ && "$h" =~ ^[1-9][0-9]*$ ]] || return 1
    g=$(gcd "$w" "$h")
    echo "$(( w / g )):$(( h / g ))"
}

while true; do
    WALLPAPER="$(current_wallpaper)"

    # No image wallpaper (yet), or it's unchanged and the effects image exists
    if [[ ! -f "$WALLPAPER" ]] || {
        [[ -f "$STATE" ]] &&
        [[ "$(cat "$STATE")" == "$WALLPAPER" ]] &&
        [[ -f "$EFFECTSWALLPAPEROUTPUT" ]]
    }; then
        sleep 1
        continue
    fi

    echo "New wallpaper detected: $WALLPAPER"

    CROP=()
    if ASPECT="$(screen_aspect)"; then
        echo "Aspect Ratio: $ASPECT"
        CROP=(-gravity center -crop "$ASPECT" +repage)
        SCREEN_TRIES=0
    elif (( ${SCREEN_TRIES:=0} < 15 )); then
        # Right after login KScreen often has no outputs yet ("There are no
        # outputs - creating placeholder screen"); give it a moment.
        (( SCREEN_TRIES++ ))
        sleep 2
        continue
    else
        echo "Couldn't read the screen resolution, not cropping." >&2
        SCREEN_TRIES=0
    fi

    # Create effects wallpaper for app drawer; state is recorded only on success
    if ! magick "$WALLPAPER" \
        -fill black -colorize 70% \
        -blur 0x15 \
        "${CROP[@]}" \
        -resize 1920x \
        "$TMPOUTPUT" || ! mv -f "$TMPOUTPUT" "$EFFECTSWALLPAPEROUTPUT"; then
        echo "magick failed on $WALLPAPER, retrying in 5s" >&2
        rm -f "$TMPOUTPUT"
        sleep 5
        continue
    fi
    echo "$WALLPAPER" > "$STATE"
done
