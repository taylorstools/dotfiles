#!/usr/bin/env bash

DEVICE="leds:asus::kbd_backlight"

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
        -h|--help)
            echo "Usage: $(basename "$0") [-set VALUE | -get]"
            echo "  No args: cycle through 0/34/67/100"
            echo "  -set N : set brightness to N (0-100)"
            echo "  -get   : print current brightness percentage"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

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