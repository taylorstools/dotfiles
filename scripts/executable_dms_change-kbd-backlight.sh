#!/usr/bin/env bash

# The LED name is not the same on every machine -- asus::kbd_backlight on the
# PX13, tpacpi::kbd_backlight on ThinkPads that have one -- and some machines
# have no backlit keyboard at all. Find whatever is there rather than naming it,
# and treat "nothing is there" as a no-op so the lid and Fn-key paths that call
# this on a machine without one do not fail.
find_device() {
    local led
    for led in /sys/class/leds/*kbd_backlight*; do
        [[ -e "$led/brightness" ]] || continue
        printf 'leds:%s\n' "$(basename "$led")"
        return 0
    done
    return 1
}

DEVICE="$(find_device || true)"

# Parse arguments
NEXT=""
ACTION="cycle"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -set)
            if [[ -z "$2" || ! "$2" =~ ^[0-9]+$ ]] || (( $2 < 0 || $2 > 100 )); then
                echo "Error: -set requires an integer between 0 and 100" >&2
                exit 1
            fi
            NEXT="$2"
            ACTION="set"
            shift 2
            ;;
        -get)
            ACTION="get"
            shift
            ;;
        -has-device)
            ACTION="has-device"
            shift
            ;;
        -h|--help)
            echo "Usage: $(basename "$0") [-set VALUE | -get | -has-device]"
            echo "  No args     : cycle through 0/34/67/100"
            echo "  -set N      : set brightness to N (0-100)"
            echo "  -get        : print current brightness percentage"
            echo "  -has-device : exit 0 if this machine has a keyboard backlight"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# Handle -has-device: a probe for callers, so they can skip their own work
if [[ "$ACTION" == "has-device" ]]; then
    [[ -n "$DEVICE" ]]
    exit
fi

# No backlit keyboard on this machine. -get prints nothing and fails so callers
# can tell it apart from a real 0%; the rest quietly do nothing.
if [[ -z "$DEVICE" ]]; then
    [[ "$ACTION" == "get" ]] && exit 1
    exit 0
fi

# Handle -get: just print and exit
if [[ "$ACTION" == "get" ]]; then
    dms brightness get "$DEVICE" | grep -oP '\d+(?=%)' || exit 1
    exit 0
fi

# If cycling, figure out the next step
if [[ "$ACTION" == "cycle" ]]; then
    CURRENT=$(dms brightness get "$DEVICE" | grep -oP '\d+(?=%)') || exit 1

    if (( CURRENT < 34 )); then
        NEXT=34
    elif (( CURRENT < 67 )); then
        NEXT=67
    elif (( CURRENT < 100 )); then
        NEXT=100
    else
        NEXT=0
    fi
fi

# Apply brightness
dms brightness set "$DEVICE" "$NEXT"
