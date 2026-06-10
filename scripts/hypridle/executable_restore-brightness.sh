#!/usr/bin/env bash

set -euo pipefail

# Kill the dim brightness script if it is running
PIDFILE="$XDG_RUNTIME_DIR/save-brightness-and-dim.sh.pid"

if [ -f "$PIDFILE" ]; then
    oldpid="$(cat "$PIDFILE")"
    if kill -0 "$oldpid" 2>/dev/null; then
        kill "$oldpid" 2>/dev/null || true
        for _ in $(seq 1 200); do
            kill -0 "$oldpid" 2>/dev/null || break
            sleep 0.01
        done
    fi
    rm -f "$PIDFILE"
fi

niri msg action power-on-monitors

STATE="/tmp/hypridle-dimmed"

if [[ -f "$STATE" ]]; then
    dms ipc call settings set osdBrightnessEnabled false
    trap 'dms ipc call settings set osdBrightnessEnabled true || true' EXIT INT TERM

    brightnessctl -c backlight -r || true
    rm -f "$STATE"

    sleep 0.3   # let DMS register the restore while the OSD is still suppressed
fi