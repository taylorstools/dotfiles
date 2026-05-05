#!/usr/bin/env bash

set -euo pipefail

PIDFILE="$XDG_RUNTIME_DIR/save-brightness-and-dim.sh.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    exit 0
fi
echo $$ > "$PIDFILE"

cleanup() {
    rm -f "$PIDFILE"
}
trap cleanup EXIT

STATE="/tmp/hypridle-dimmed"
KBD_SCRIPT="$HOME/scripts/dms_change-kbd-backlight.sh"
KBD_STATE="/tmp/dms-kbdbacklight"
mkdir -p "$(dirname "$STATE")"

# Snapshot brightness once
if [[ ! -f "$STATE" ]]; then
    brightnessctl -c backlight -s
    "$KBD_SCRIPT" -get > "$KBD_STATE"
    touch "$STATE"
fi

# Compute dimmed brightness
max=$(brightnessctl -c backlight m)
target=$(( max / 12 ))
(( target < 1 )) && target=1

# Smoothly dim
while :; do
    cur=$(brightnessctl -c backlight g)
    (( cur <= target )) && break

    step=$(( max * 3 / 100 ))
    (( step < 1 )) && step=1

    brightnessctl -c backlight -q set "$(( cur - step ))"
    sleep 0.03
done

# Turn off keyboard backlight
"$KBD_SCRIPT" -set 0