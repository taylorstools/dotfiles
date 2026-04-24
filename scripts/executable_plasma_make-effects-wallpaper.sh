#!/usr/bin/env bash

set -euo pipefail

mkdir -p "$HOME/.dotfiles/Wallpapers"
EFFECTSWALLPAPEROUTPUT="$HOME/.config/.EffectsWallpaper.png"
STATE="/tmp/plasma-current-wallpaper"

gcd() {
    local -n _ret=$1
    local a=$2 b=$3 t
    while (( b )); do
        t=$(( a % b ))
        a=$b
        b=$t
    done
    _ret=$a
}

while true; do
	WALLPAPER=$(grep -r "Image=" ~/.config/plasma-org.kde.plasma.desktop-appletsrc \
		| head -1 \
		| cut -d'=' -f2 \
		| sed 's|file://||')

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

	# Run magick if Plasma has new wallpaper
	echo "New wallpaper detected."
	echo "$WALLPAPER" > "$STATE"

	# Get screen resolution
	read -r SCREEN_W SCREEN_H < <(
		kscreen-doctor -o | awk '/Modes:/ {match($0, /([0-9]+)x([0-9]+)@[0-9.]+\*/, m); print m[1], m[2]; exit}'
	)

	echo "Resolution: ${SCREEN_W}x${SCREEN_H}"

	gcd g "$SCREEN_W" "$SCREEN_H"
	ASPECT="$(( SCREEN_W / g )):$(( SCREEN_H / g ))"

	echo "Aspect Ratio: $ASPECT"

	# Create effects wallpaper for app drawer
	echo "Running magick on wallpaper."
	magick "$WALLPAPER" \
		-fill black -colorize 70% \
		-blur 0x15 \
		-gravity center -crop "$ASPECT" +repage \
		-resize 1920x \
		"$EFFECTSWALLPAPEROUTPUT"
done