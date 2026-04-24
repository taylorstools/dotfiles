#!/usr/bin/env bash

# If overlay is off, turn it on
# If overlay is on, make it darker

PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/dim-overlay.pid"
LEVEL_FILE="${XDG_RUNTIME_DIR:-/tmp}/dim-overlay.level"
SHARE="$HOME/.local/share/dim-overlay"
PY_FILE="$SHARE/dim-overlay.py"
ENV="$SHARE/env"

read_const() {
    awk -F'=' -v k="$1" '$1 ~ "^"k {gsub(/[ \t]/,"",$2); print $2; exit}' "$PY_FILE" 2>/dev/null
}
DEF=$(read_const  "OPACITY_DEF");  [[ -z "$DEF"  ]] && DEF="0.40"
STEP=$(read_const "OPACITY_STEP"); [[ -z "$STEP" ]] && STEP="0.05"
MAX=$(read_const  "OPACITY_MAX");  [[ -z "$MAX"  ]] && MAX="0.95"

PIDS=""
if [[ -f "$PID_FILE" ]]; then
    P=$(cat "$PID_FILE" 2>/dev/null || true)
    if [[ -n "$P" ]] && kill -0 "$P" 2>/dev/null; then
        PIDS="$P"
    fi
fi
[[ -z "$PIDS" ]] && PIDS=$(pgrep -f "dim-overlay\.py" || true)

if [[ -n "$PIDS" ]]; then
    kill -USR1 $PIDS          # already running → darker
    CUR=$( [[ -f "$LEVEL_FILE" ]] && cat "$LEVEL_FILE" || echo "$DEF" )
    NEW=$(awk -v c="$CUR" -v s="$STEP" -v m="$MAX" 'BEGIN {
        v = c + s; if (v > m) v = m; printf "%.2f", v
    }')
    echo "$NEW" > "$LEVEL_FILE"
else
    if [[ ! -e "$ENV/bin/dim-overlay-python" ]]; then
        echo "dim-overlay: Nix env not built at $ENV." >&2
        echo "  Rebuild with: (cd $SHARE && nix-build -o env default.nix)" >&2
        exit 1
    fi
    setsid nohup "$ENV/bin/dim-overlay-python" "$PY_FILE" \
        >/dev/null 2>&1 </dev/null &
    echo "$DEF" > "$LEVEL_FILE"
fi