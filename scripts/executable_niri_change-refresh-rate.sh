#!/usr/bin/env bash

set -euo pipefail

OUTPUT="eDP-1"

# Get all available WxH@Hz modes
mapfile -t ALL_MODES < <(
    niri msg outputs | awk -v out="$OUTPUT" '
    $0 ~ "Output .*\\(" out "\\)" { in_output=1 }
    in_output && $0 ~ "Available modes:" { in_modes=1; next }
    in_modes && /^[[:space:]]+[0-9]/ {
        gsub(/^[[:space:]]+/, "", $0)
        split($0, a, " ")
        print a[1]
    }
    in_output && NF==0 { in_output=0; in_modes=0 }
    '
)

if [[ ${#ALL_MODES[@]} -eq 0 ]]; then
    echo "No modes found for $OUTPUT"
    exit 1
fi

# Determine maximum resolution (by pixel count)
MAX_RESOLUTION=$(
    printf '%s\n' "${ALL_MODES[@]}" |
    awk -F'[@x]' '
    {
        pixels = $1 * $2
        if (pixels > max) {
            max = pixels
            res = $1 "x" $2
        }
    }
    END { print res }
    '
)

# Keep only modes matching max resolution
MODES=()
for mode in "${ALL_MODES[@]}"; do
    [[ "${mode%@*}" == "$MAX_RESOLUTION" ]] && MODES+=("$mode")
done

if [[ ${#MODES[@]} -lt 2 ]]; then
    echo "Only one refresh rate available for $MAX_RESOLUTION"
    exit 0
fi

# Get the currently active mode
CURRENT_MODE=$(niri msg outputs | awk -v out="$OUTPUT" '
$0 ~ "Output .*\\(" out "\\)" { in_output=1 }
in_output && $0 ~ "Current mode:" {
    gsub(/.*Current mode: /, "", $0)
    split($0, a, " ")
    print a[1] "@" a[3]
}
')

# Find next refresh rate (wrap around)
NEXT_MODE=""
for i in "${!MODES[@]}"; do
    if [[ "${MODES[$i]}" == "$CURRENT_MODE" ]]; then
        NEXT_INDEX=$(( (i + 1) % ${#MODES[@]} ))
        NEXT_MODE="${MODES[$NEXT_INDEX]}"
        break
    fi
done

if [[ -z "$NEXT_MODE" ]]; then
    echo "Current mode not found among max-resolution modes"
    exit 1
fi

NEXT_REFRESHRATE="$(awk "BEGIN { printf \"%d\", (${NEXT_MODE##*@}) + 0.5 }")Hz"

# Set the refresh rate
niri msg output $OUTPUT mode $NEXT_MODE

sleep 1
dms ipc call toast info "Refresh rate set to $NEXT_REFRESHRATE"