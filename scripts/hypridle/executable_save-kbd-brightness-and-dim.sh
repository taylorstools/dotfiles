#!/usr/bin/env bash

set -euo pipefail

KBD_SCRIPT="$HOME/scripts/dms_change-kbd-backlight.sh"
KBD_STATE="/tmp/dms-kbdbacklight"

# Nothing to dim on a machine with no backlit keyboard. Checked before the
# pidfile so the restore side has nothing to clean up either.
"$KBD_SCRIPT" -has-device || exit 0

PIDFILE="$XDG_RUNTIME_DIR/save-kbd-brightness-and-dim.sh.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    exit 0
fi
echo $$ > "$PIDFILE"

cleanup() {
    rm -f "$PIDFILE"
}
trap cleanup EXIT

# Save current brightness only if we're not already dimmed
if [[ ! -f "$KBD_STATE" ]]; then
    "$KBD_SCRIPT" -get > "$KBD_STATE"
fi

# Turn off keyboard backlight
"$KBD_SCRIPT" -set 0
