#!/usr/bin/env bash

# Sometimes hyprlock just absorbs first key press after boot
# This script sends a dummy key press at startup to fix that

max_iterations=300  # 300 * 0.1s = 30s safety timeout
i=0

while ! pgrep -x hyprlock >/dev/null; do
    sleep 0.1
    i=$((i + 1))
    if (( i >= max_iterations )); then
        echo "hyprlock did not start within 30s, giving up" >&2
        exit 1
    fi
done

# Brief pause so hyprlock has time to establish its keyboard grab
#sleep 0.2

wtype -k Control_L