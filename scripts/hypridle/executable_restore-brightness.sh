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

# See if currently dimmed
STATE="/tmp/hypridle-dimmed"

# If dimmed, restore brightness
if [[ -f "$STATE" ]]; then
    brightnessctl -c backlight -r || true
    rm -f "/tmp/hypridle-dimmed"
fi