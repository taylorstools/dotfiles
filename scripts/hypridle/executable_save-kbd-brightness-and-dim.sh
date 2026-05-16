#!/usr/bin/env bash

set -euo pipefail

PIDFILE="$XDG_RUNTIME_DIR/save-kbd-brightness-and-dim.sh.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    exit 0
fi
echo $$ > "$PIDFILE"

cleanup() {
    rm -f "$PIDFILE"
}
trap cleanup EXIT

KBD_SCRIPT="$HOME/scripts/dms_change-kbd-backlight.sh"
KBD_STATE="/tmp/dms-kbdbacklight"

# Save current brightness to file
"$KBD_SCRIPT" -get > "$KBD_STATE"

# Turn off keyboard backlight
"$KBD_SCRIPT" -set 0