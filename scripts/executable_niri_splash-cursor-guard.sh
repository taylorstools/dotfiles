#!/usr/bin/env bash
#
# Last line of defence for the cursor at login. niri-splash blanks niri's
# cursor theme at logout (through custom/cursor-startup.kdl) and restores it
# when the splash lifts. If no splash shows up within 3 s -- disabled,
# crashed before mapping, or not installed at all -- nothing else is going to
# restore it, so this does. Keyed on content so a file repurposed by hand is
# left alone; niri live-reloads the change.
#
# This used to be part of niri_set-wallpaper.sh, from when swaybg drew the
# overview backdrop (now the shell's Wallpaper/Backdrop.qml).

set -uo pipefail

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
SPLASH_FLAG="$RUNTIME/niri-splash.up"
CURSOR_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/niri/custom/cursor-startup.kdl"

SPLASH_TRIES=60    # 60 * 0.05s = 3s waiting for the splash

# No wait at all on a host with no niri-splash installed.
if command -v niri-splash >/dev/null 2>&1; then
    tries="$SPLASH_TRIES"
    while [[ ! -e "$SPLASH_FLAG" && "$tries" -gt 0 ]]; do
        sleep 0.05
        tries=$(( tries - 1 ))
    done
fi

if [[ ! -e "$SPLASH_FLAG" && -f "$CURSOR_FILE" ]] \
    && grep -q 'niri-splash-blank' "$CURSOR_FILE"; then
    printf '%s\n' '// niri-splash: no cursor override active' > "$CURSOR_FILE"
fi
