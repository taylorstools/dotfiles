#!/usr/bin/env bash

set -euo pipefail

KBD_SCRIPT="$HOME/scripts/dms_change-kbd-backlight.sh"
KBD_STATE="/tmp/dms-kbdbacklight"

# Restore keyboard backlight
if [[ -f "$KBD_STATE" ]]; then
    "$KBD_SCRIPT" -set "$(cat "$KBD_STATE")" || true
    rm -f "$KBD_STATE"
fi