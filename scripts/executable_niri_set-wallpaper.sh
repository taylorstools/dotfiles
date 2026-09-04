#!/usr/bin/env bash
#
# Own the session's swaybg instance.
#
# swaybg was being started in two places -- once at login from startup.kdl,
# and again by niri_make-effects-wallpaper.sh on every wallpaper change --
# and neither stopped the one before it, so instances piled up for as long as
# the session lasted (visible as repeated "wallpaper" entries in
# `niri msg layers`). Everything that puts a wallpaper up goes through here
# instead: it starts the new swaybg, waits for its surface to exist, and only
# then kills the one it started last, so no frame is ever drawn with no
# wallpaper on it.
#
# Usage:
#   niri_set-wallpaper.sh [IMAGE]
#       Replace the current wallpaper. Defaults to the effects wallpaper.
#
#   niri_set-wallpaper.sh --at-login [IMAGE]
#       As above, but first hold until the startup splash is covering the
#       screen (see myOptions.niri-splash), and sweep up any swaybg left
#       behind by a session that did not exit cleanly.

set -uo pipefail

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PIDFILE="$RUNTIME/swaybg.pid"
SPLASH_FLAG="$RUNTIME/niri-splash.up"
CURSOR_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/niri/custom/cursor-startup.kdl"

SPLASH_TRIES=60    # 60 * 0.05s = 3s waiting for the splash
SURFACE_TRIES=20   # 20 * 0.05s = 1s waiting for the new wallpaper to appear

at_login=0
if [[ "${1:-}" == "--at-login" ]]; then
    at_login=1
    shift
fi
WALLPAPER="${1:-$HOME/.config/.EffectsWallpaper.png}"

count_wallpaper_surfaces() {
    niri msg --json layers 2>/dev/null \
        | grep -o '"namespace":"wallpaper"' \
        | wc -l
}

if (( at_login )); then
    # Anything already running at login belongs to a session that is gone.
    # Done before the wait below, not after: niri_make-effects-wallpaper.sh
    # starts at the same moment and will call this script itself once DMS
    # answers, and sweeping up afterwards could take that instance with it.
    pkill -u "$(id -u)" -x swaybg 2>/dev/null
    rm -f "$PIDFILE"

    # swaybg only has to decode a PNG, while the splash has to bring up a GTK
    # toolkit first, so without this swaybg wins the race and its wallpaper is
    # visible for a moment before the splash lands on top of it -- the exact
    # flash the splash exists to remove. No wait at all on a host with no
    # niri-splash installed.
    if command -v niri-splash >/dev/null 2>&1; then
        tries="$SPLASH_TRIES"
        while [[ ! -e "$SPLASH_FLAG" && "$tries" -gt 0 ]]; do
            sleep 0.05
            tries=$(( tries - 1 ))
        done
    fi

    # Last line of defence for the cursor. niri-splash blanks niri's cursor
    # theme at logout (through this include) and restores it when the splash
    # lifts. If no splash appeared in the time above -- disabled, crashed
    # before mapping, or not installed at all -- nothing else is going to
    # restore it, so do it here. Keyed on content so a file the user has
    # repurposed is left alone; niri live-reloads the change.
    if [[ ! -e "$SPLASH_FLAG" && -f "$CURSOR_FILE" ]] \
        && grep -q 'niri-splash-blank' "$CURSOR_FILE"; then
        printf '%s\n' '// niri-splash: no cursor override active' > "$CURSOR_FILE"
    fi
fi

old_pid=""
[[ -f "$PIDFILE" ]] && old_pid="$(cat "$PIDFILE" 2>/dev/null)"

before="$(count_wallpaper_surfaces)"

swaybg -m fill -i "$WALLPAPER" >/dev/null 2>&1 &
new_pid=$!
echo "$new_pid" > "$PIDFILE"

# Wait for the new wallpaper to be on screen before taking the old one away,
# so the swap never uncovers a bare background. Bounded, because a swaybg that
# fails to start must not leave the previous one running forever.
tries="$SURFACE_TRIES"
while [[ "$(count_wallpaper_surfaces)" -le "$before" && "$tries" -gt 0 ]]; do
    kill -0 "$new_pid" 2>/dev/null || break
    sleep 0.05
    tries=$(( tries - 1 ))
done

if [[ -n "$old_pid" && "$old_pid" != "$new_pid" ]]; then
    kill "$old_pid" 2>/dev/null
fi

# Deliberately no `wait`: this is called from inside the poll loop in
# niri_make-effects-wallpaper.sh, which must not block. swaybg is reparented
# and keeps running.
#
# The explicit success matters too -- that caller runs under `set -e`, and a
# `kill` of an already-dead old instance would otherwise take its loop down.
exit 0
