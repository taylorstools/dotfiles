#!/usr/bin/env bash

if pidof hypridle > /dev/null; then
    # Toggle keep awake on
    pkill -x hypridle
    notify-send -a "Keep Awake ON" "PC will now stay awake." -i "changes-allow-symbolic"
else
    # Toggle keep awake off
    hypridle &
    notify-send -a "Keep Awake OFF" "PC will now dim, lock, and sleep." -i "changes-prevent-symbolic"
fi