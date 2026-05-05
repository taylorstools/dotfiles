#!/usr/bin/env bash

set -euo pipefail

# Kill the dim brightness script if it is running
PIDFILE="$XDG_RUNTIME_DIR/save-brightness-and-dim.sh.pid"

if [ -f "$PIDFILE" ]; then
    oldpid="$(cat "$PIDFILE")"
    if kill -0 "$oldpid" 2>/dev/null; then
        kill "$oldpid"
        wait "$oldpid" 2>/dev/null || true
    fi
    rm -f "$PIDFILE"
fi

niri msg action power-on-monitors

STATE="/tmp/hypridle-dimmed"
KBD_SCRIPT="$HOME/scripts/dms_change-kbd-backlight.sh"
KBD_STATE="/tmp/dms-kbdbacklight"

# If dimmed, restore screen brightness
if [[ -f "$STATE" ]]; then
    brightnessctl -c backlight -r || true
    rm -f "$STATE"
fi

# Restore keyboard backlight
if [[ -f "$KBD_STATE" ]]; then
    "$KBD_SCRIPT" -set "$(cat "$KBD_STATE")" || true
    rm -f "$KBD_STATE"
fi