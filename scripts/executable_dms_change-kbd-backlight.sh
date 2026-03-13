#!/usr/bin/env bash

DEVICE="leds:asus::kbd_backlight"

# Get current brightness percentage
CURRENT=$(dms brightness get "$DEVICE" | grep -oP '\d+(?=%)') || exit 1

# Determine next step
if (( CURRENT < 34 )); then
    NEXT=34
elif (( CURRENT < 67 )); then
    NEXT=67
elif (( CURRENT < 100 )); then
    NEXT=100
else
    NEXT=0
fi

# Apply brightness
dms brightness set "$DEVICE" "$NEXT"