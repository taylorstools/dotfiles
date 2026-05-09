#!/usr/bin/env bash

set -euo pipefail

KBD_SCRIPT="$HOME/scripts/dms_change-kbd-backlight.sh"
KBD_STATE="/tmp/dms-kbdbacklight"

# Save current brightness to file
"$KBD_SCRIPT" -get > "$KBD_STATE"

# Turn off keyboard backlight
"$KBD_SCRIPT" -set 0