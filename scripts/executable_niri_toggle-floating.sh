#!/usr/bin/env bash

set -euo pipefail

FloatWidth=900
FloatHeight=650

WindowJson=$(niri msg --json focused-window 2>/dev/null) || {
  echo "No focused window (or niri IPC unavailable)." >&2
  exit 1
}

if [ -z "$WindowJson" ] || [ "$WindowJson" = "null" ]; then
  echo "No focused window." >&2
  exit 1
fi

IsFloating=$(jq -r '.is_floating' <<<"$WindowJson")

if [ "$IsFloating" = "true" ]; then
  niri msg action toggle-window-floating
else
  niri msg action toggle-window-floating
  niri msg action set-window-width "$FloatWidth"
  niri msg action set-window-height "$FloatHeight"
  
  # Wait up to ~500ms for the committed size to catch up, then center.
  for _ in $(seq 1 25); do
    read -r W H < <(niri msg --json focused-window \
      | jq -r '.layout.window_size | "\(.[0]|floor) \(.[1]|floor)"')
    [ "$W" = "$FloatWidth" ] && [ "$H" = "$FloatHeight" ] && break
    sleep 0.02
  done
  niri msg action center-window
fi