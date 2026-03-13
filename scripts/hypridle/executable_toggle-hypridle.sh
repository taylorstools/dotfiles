#!/usr/bin/env bash

if pidof hypridle > /dev/null; then
    # Toggle keep awake on
    pkill -x hypridle
    dms ipc call toast info "PC will now stay awake"
else
    # Toggle keep awake off
    hypridle &
    dms ipc call toast info "PC will now dim, lock, and sleep"
fi