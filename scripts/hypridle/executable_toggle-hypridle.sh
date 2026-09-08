#!/usr/bin/env bash

# hypridle is managed by hypridle.service, the user unit shipped inside the
# nixpkgs hypridle package and pulled in by environment.systemPackages. Ask
# systemd rather than pidof: systemd is the only thing that knows whether the
# daemon it supervises is meant to be running.

if systemctl --user is-active --quiet hypridle.service; then
    # Toggle keep awake on
    systemctl --user stop hypridle.service
    dms ipc call toast info "PC will now stay awake"
else
    # Toggle keep awake off
    systemctl --user start hypridle.service
    dms ipc call toast info "PC will now dim, lock, and sleep"
fi
