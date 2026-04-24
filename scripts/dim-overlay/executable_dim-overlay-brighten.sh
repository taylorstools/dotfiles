#!/usr/bin/env bash

# At (or below) OPACITY_DEF, turn off
# Above default, brighter by one step

PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/dim-overlay.pid"
LEVEL_FILE="${XDG_RUNTIME_DIR:-/tmp}/dim-overlay.level"
PY_FILE="$HOME/.local/share/dim-overlay/dim-overlay.py"

# Find overlay
PIDS=""
if [[ -f "$PID_FILE" ]]; then
    P=$(cat "$PID_FILE" 2>/dev/null || true)
    if [[ -n "$P" ]] && kill -0 "$P" 2>/dev/null; then
        PIDS="$P"
    fi
fi
[[ -z "$PIDS" ]] && PIDS=$(pgrep -f "dim-overlay\.py" || true)
[[ -z "$PIDS" ]] && exit 0

read_const() {
    awk -F'=' -v k="$1" '$1 ~ "^"k {gsub(/[ \t]/,"",$2); print $2; exit}' "$PY_FILE" 2>/dev/null
}
DEF=$(read_const  "OPACITY_DEF");  [[ -z "$DEF"  ]] && DEF="0.40"
STEP=$(read_const "OPACITY_STEP"); [[ -z "$STEP" ]] && STEP="0.05"
MIN=$(read_const  "OPACITY_MIN");  [[ -z "$MIN"  ]] && MIN="0.05"

if [[ -f "$LEVEL_FILE" ]]; then
    CUR=$(cat "$LEVEL_FILE")
else
    CUR="$DEF"
fi

# At or below default: hand off to kill script
if awk -v c="$CUR" -v d="$DEF" 'BEGIN { exit !(c <= d + 0.001) }'; then
    exec "$(dirname "$0")/kill-dim-overlay.sh"
fi

# Otherwise brighten by one step
kill -USR2 $PIDS
NEW=$(awk -v c="$CUR" -v s="$STEP" -v n="$MIN" 'BEGIN {
    v = c - s; if (v < n) v = n; printf "%.2f", v
}')
echo "$NEW" > "$LEVEL_FILE"