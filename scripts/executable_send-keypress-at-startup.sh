#!/usr/bin/env bash

# Sometimes hyprlock just absorbs first key press after boot
# This script sends a dummy key press at startup to fix that

max_iterations=300  # 300 * 0.1s = 30 sec timeout
i=0

while ! pgrep -x hyprlock >/dev/null; do
    sleep 0.1
    i=$((i + 1))
    if (( i >= max_iterations )); then
        echo "hyprlock did not start within 30s, giving up..."
        exit 1
    fi
done

elapsed_ms=$((i * 100))

# Send Control key
ydotool key 29:1 29:0