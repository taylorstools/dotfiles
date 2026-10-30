#!/usr/bin/env bash

# Night light lives in the Quickshell config (Services/NightLight.qml).
qs ipc call night enable

MIN=2500
MAX=6000
STEP=100
DEFAULT=2500

# Current value
CURRENT=$(qs ipc call night getTemp 2>/dev/null || echo "$DEFAULT")

yad \
  --title="Night Mode Strength" \
  --scale \
  --hide-value \
  --enforce-step \
  --invert \
  --mark=6000K:6000 --mark=2500K:2500 \
  --text="<span size='x-large' weight='bold'>󰖨   Night Mode Strength</span>" \
  --borders=30 \
  --min-value="$MIN" \
  --max-value="$MAX" \
  --value="$CURRENT" \
  --step="$STEP" \
  --print-partial \
  --center \
  --width=500 \
  --button="Close:0" |
while read -r temp; do
  LAST="$temp"
  kill "$JOB" 2>/dev/null
  (
    qs ipc call night setTemp "$LAST"
  ) &
  JOB=$!
done