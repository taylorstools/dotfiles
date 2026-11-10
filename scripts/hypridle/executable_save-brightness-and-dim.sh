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
trap cleanup EXIT INT TERM

STATE="/tmp/hypridle-dimmed"

if [[ ! -f "$STATE" ]]; then
    brightnessctl -c backlight -s
    touch "$STATE"
fi

# Steps go through the shell with the OSD off (the last argument). Timing
# the OSD off with `osd suppress` lost a race: the shell polls the backlight,
# so the last step could land after the suppression ended and show the OSD.
# Without the shell, brightnessctl sets it directly.
set_level() {
    qs ipc call brightness set "$1" false 2>/dev/null \
        || brightnessctl -c backlight -q set "$1%"
}

target=10
step=3
max=$(brightnessctl -c backlight m)
pct=$(( $(brightnessctl -c backlight g) * 100 / max ))

# Each qs call takes ~60 ms, so no sleep is needed to pace the fade.
while (( pct > target )); do
    pct=$(( pct - step ))
    (( pct < target )) && pct=$target
    set_level "$pct"
done
