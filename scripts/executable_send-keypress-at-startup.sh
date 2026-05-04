#!/usr/bin/env bash

# Sometimes hyprlock just absorbs first key press after boot
# This script sends a dummy key press at startup to fix that

LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/hyprlock-warmup.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

log "--- script started ---"

max_iterations=300  # 300 * 0.1s = 30s safety timeout
i=0

while ! pgrep -x hyprlock >/dev/null; do
    sleep 0.1
    i=$((i + 1))
    if (( i >= max_iterations )); then
        log "hyprlock did not start within 30s, giving up"
        exit 1
    fi
done

elapsed_ms=$((i * 100))
log "hyprlock detected after ${elapsed_ms}ms (${i} iterations)"

# Brief pause so hyprlock has time to establish its keyboard grab
#sleep 0.2

if wtype -k Control_L 2>>"$LOG_FILE"; then
    log "wtype Control_L sent successfully"
else
    log "wtype failed with exit code $?"
    exit 1
fi

log "--- script finished ---"