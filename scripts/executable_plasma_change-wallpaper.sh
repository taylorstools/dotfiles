#!/usr/bin/env bash

# Sets a random Plasma wallpaper from ~/.dotfiles/Wallpapers, never the one
# already showing.
#
#   plasma_change-wallpaper.sh          change it once (the panel button)
#   plasma_change-wallpaper.sh --loop   change it now, then every
#                                       INTERVAL_MINUTES (from autostart)
#
# The loop runs for the whole session, so no failure may end it: no `set -e`,
# every step checks for itself, same as plasma_make-effects-wallpaper.sh
# (which notices each change and rebuilds the app drawer background).
set -uo pipefail

# How often --loop changes the wallpaper.
INTERVAL_MINUTES=15

WALLPAPER_DIR="$HOME/.dotfiles/Wallpapers"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
# The wallpaper this script last set; its mtime is when. Plasma writes
# appletsrc lazily, so reading it back straight after a change can still give
# the old image. In the runtime dir, which is emptied every boot.
STATE="$RUNTIME/plasma-change-wallpaper"
# Held by the --loop instance, so a second loop (a re-run autostart, a manual
# start) exits instead of doubling the change rate.
LOCK="$RUNTIME/plasma-change-wallpaper.lock"

INTERVAL=$(( INTERVAL_MINUTES * 60 ))
(( INTERVAL > 0 )) || INTERVAL=900

now() { printf '%(%s)T' -1; }

current_wallpaper() {
    local last
    if [[ -f "$STATE" ]] && last="$(<"$STATE")" && [[ -f "$last" ]]; then
        echo "$last"
        return
    fi
    # The Image= of the desktop's org.kde.image wallpaper, not the slideshow's.
    awk -F= '
        /^\[/ { inimage = /\[Wallpaper\]\[org\.kde\.image\]\[General\]$/ }
        inimage && $1 == "Image" { sub(/^[^=]*=/, ""); sub(/^file:\/\//, ""); print; exit }
    ' "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null
}

# Picks a random image other than the current one, or fails.
pick_wallpaper() {
    local current args
    current="$(current_wallpaper)"
    args=(
        "$WALLPAPER_DIR" -maxdepth 1 -type f
        \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \)
    )
    [[ -f "$current" ]] && args+=( ! -samefile "$current" )
    find "${args[@]}" 2>/dev/null | shuf -n 1
}

# Sets one new wallpaper. Records it only on success.
change_once() {
    local wallpaper
    wallpaper="$(pick_wallpaper)"
    if [[ -z "$wallpaper" ]]; then
        echo "No other wallpaper found in $WALLPAPER_DIR" >&2
        return 1
    fi
    # Fails until plasmashell is up and serving its D-Bus interface, which
    # right after login it may not be yet.
    if ! plasma-apply-wallpaperimage "$wallpaper"; then
        echo "plasma-apply-wallpaperimage failed on $wallpaper" >&2
        return 1
    fi
    echo "Wallpaper set: $wallpaper"
    echo "$wallpaper" > "$STATE" || true
}

if [[ "${1:-}" != "--loop" ]]; then
    change_once
    exit
fi

exec 9>"$LOCK"
if ! flock -n 9; then
    echo "Another wallpaper loop is already running." >&2
    exit 0
fi

echo "Changing the wallpaper every $INTERVAL_MINUTES min"

# Once at login, retrying (longer each time, up to a minute) until
# plasmashell takes it.
delay=2
until change_once; do
    sleep "$delay"
    (( delay = delay * 2 > 60 ? 60 : delay * 2 ))
done

# Then on the interval. Timed against the wall clock rather than a single
# long sleep: sleep doesn't count time suspended, and the panel button
# writes STATE too, so a change made by hand restarts the count. A failed
# change leaves STATE alone and is retried on the next check.
while true; do
    sleep 10
    last=$(stat -c %Y "$STATE" 2>/dev/null) || last=0
    (( $(now) - last >= INTERVAL )) || continue
    if ! change_once; then
        # Don't retry every 10s while plasmashell is down; try again in a
        # minute by backdating STATE's mtime to a minute short of due.
        touch -d "@$(( $(now) - INTERVAL + 60 ))" "$STATE" 2>/dev/null || sleep 60
    fi
done
