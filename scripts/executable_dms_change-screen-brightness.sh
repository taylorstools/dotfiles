#!/usr/bin/env bash

set -euo pipefail

STEP=5

TMP_FILE="/tmp/dms-backlightdevice"

# Get backlight device and save to file
if [[ ! -f "$TMP_FILE" ]]; then
    dms ipc call brightness list \
        | grep -oE '^backlight:[^ ]+' \
        | head -n1 > "$TMP_FILE"
fi

BACKLIGHT=$(<"$TMP_FILE")

# Get current brightness
current=$(dms brightness get "$BACKLIGHT" | grep -oE '[0-9]+%' | tr -d '%')

case "${1:-}" in
  -decrease)
    new=$((current - STEP))
    ;;
  -increase)
    # Round down to nearest step size
    rounded=$(( (current / STEP) * STEP ))
    new=$((rounded + STEP))
    ;;
  *)
    echo "Usage: $0 {-increase|-decrease}"
    exit 1
    ;;
esac

# Set brightness level
dms brightness set "$BACKLIGHT" "$new"