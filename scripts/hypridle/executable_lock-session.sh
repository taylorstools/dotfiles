#!/usr/bin/env bash

# Locks the session with the shell's lock screen (.quickshell/Lock/Lock.qml)
# and returns once niri has confirmed the lock. Exits 1 if it never does;
# hypridle's lock_cmd and niri_lock-at-startup.sh then quit niri rather than
# leave the session open.
#
# The shell may be restarting (it comes back within a second or two), so
# reaching it is retried for a few seconds before that counts as a failure.
#
# --force is still accepted: callers pass it from the hyprlock days, when it
# cleared a hyprlock that had deadlocked after unlocking.

set -uo pipefail

for _ in $(seq 1 50); do
    qs ipc call lock lock >/dev/null 2>&1 && break
    sleep 0.1
done

for _ in $(seq 1 50); do
    if [[ "$(qs ipc call lock isSecure 2>/dev/null)" == "true" ]]; then
        # From here on, the lock screen dying ends the session (lock-guard.sh).
        if ! systemctl --user is-active --quiet lock-guard.service; then
            systemctl --user reset-failed lock-guard.service 2>/dev/null || true
            systemd-run --user --quiet --collect --unit=lock-guard.service \
                --property=PartOf=graphical-session.target \
                --setenv=PATH="$PATH" \
                --setenv=WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
                --setenv=NIRI_SOCKET="${NIRI_SOCKET:-}" \
                "$HOME/scripts/hypridle/lock-guard.sh"
        fi
        exit 0
    fi
    sleep 0.1
done

echo "the lock screen never confirmed the lock" >&2
exit 1
