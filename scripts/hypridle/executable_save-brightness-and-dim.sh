#!/usr/bin/env bash
set -euo pipefail

PIDFILE="$XDG_RUNTIME_DIR/save-brightness-and-dim.sh.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    exit 0
fi
echo $$ > "$PIDFILE"

cleanup() {
    dms ipc call settings set osdBrightnessEnabled true || true
    rm -f "$PIDFILE"
}
trap cleanup EXIT INT TERM

STATE="/tmp/hypridle-dimmed"

if [[ ! -f "$STATE" ]]; then
    brightnessctl -c backlight -s
    touch "$STATE"
fi

max=$(brightnessctl -c backlight m)
target=$(( max / 10 ))
(( target < 1 )) && target=1

step=$(( max * 3 / 100 ))
(( step < 1 )) && step=1

dms ipc call settings set osdBrightnessEnabled false

while :; do
    cur=$(brightnessctl -c backlight g)
    (( cur <= target )) && break
    brightnessctl -c backlight -q set "$(( cur - step ))"
    sleep 0.03
done