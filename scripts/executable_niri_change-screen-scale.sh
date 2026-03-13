#!/usr/bin/env bash

set -euo pipefail

OUTPUT="eDP-1"

SCALES=(
  1.0
  1.125
  1.25
  1.375
  1.5
  1.625
  1.75
  1.875
  2.0
)

usage() {
  echo "Usage: $0 --increase | --decrease"
  exit 1
}

[[ $# -eq 1 ]] || usage
ACTION="$1"
[[ "$ACTION" == "--increase" || "$ACTION" == "--decrease" ]] || usage

# Extract current scale
CURRENT_SCALE="$(
  niri msg outputs |
    awk -v out="($OUTPUT)" '
      $0 ~ out { found=1 }
      found && $1=="Scale:" { print $2; exit }
    '
)"

if [[ -z "$CURRENT_SCALE" ]]; then
  echo "Error: Could not determine current scale for $OUTPUT"
  exit 1
fi

# Find index by NUMERIC comparison
CURRENT_INDEX=-1
for i in "${!SCALES[@]}"; do
  if awk -v a="${SCALES[$i]}" -v b="$CURRENT_SCALE" 'BEGIN { exit !(a == b) }'; then
    CURRENT_INDEX="$i"
    break
  fi
done

if [[ "$CURRENT_INDEX" -eq -1 ]]; then
  echo "Error: Current scale $CURRENT_SCALE not found in scale list"
  exit 1
fi

# Increment / decrement
case "$ACTION" in
  --increase) NEW_INDEX=$((CURRENT_INDEX + 1)) ;;
  --decrease) NEW_INDEX=$((CURRENT_INDEX - 1)) ;;
esac

# Clamp to bounds
(( NEW_INDEX < 0 )) && NEW_INDEX=0
(( NEW_INDEX >= ${#SCALES[@]} )) && NEW_INDEX=$((${#SCALES[@]} - 1))

NEW_SCALE="${SCALES[$NEW_INDEX]}"

niri msg output "$OUTPUT" scale "$NEW_SCALE"

dms ipc call toast info "Scale set to $NEW_SCALE"