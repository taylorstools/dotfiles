#!/usr/bin/env bash

# Single-instance session lock.
#
# hyprlock runs as a transient systemd user unit named hyprlock.service:
#
#   - systemd refuses to create a second unit with the same name, so "only one
#     instance" is enforced atomically. `pidof hyprlock || hyprlock -q` was a
#     check-then-act race that two callers firing in the same instant both
#     passed, and with two hypridles running that happened on every timeout.
#
#   - hyprlock's stdout lands in the journal (journalctl --user -u hyprlock).
#     Spawned from a niri sh it went nowhere at all.
#
#   - a wedged hyprlock can be cleared: systemctl --user kill -s KILL hyprlock
#
# hyprlock v0.9.6 can deadlock while shutting down *after* it has already
# unlocked the session - every thread parked in futex_do_wait with the Mesa GL
# workers still alive - and the leftover process then makes every "is the
# session locked?" test answer yes forever. Callers that can only fire while
# the session is unlocked (a keybind reaching niri proves that) pass --force to
# clear such a leftover first.
#
# Exit status is hyprlock's own, or 0 if a lock was already up.

set -uo pipefail

UNIT="hyprlock.service"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

if systemctl --user is-active --quiet "$UNIT"; then
    if (( ! FORCE )); then
        exit 0
    fi

    systemctl --user kill -s KILL "$UNIT" 2>/dev/null || true
    for _ in $(seq 1 100); do
        systemctl --user is-active --quiet "$UNIT" || break
        sleep 0.05
    done
fi

systemctl --user reset-failed "$UNIT" 2>/dev/null || true

# PartOf=graphical-session.target so the lock dies with the session rather than
# outliving niri in app.slice. --wait propagates hyprlock's exit code, which
# lock_cmd relies on to decide whether to fall back to quitting niri.
exec systemd-run --user --quiet --wait --collect --unit="$UNIT" \
    --property=PartOf=graphical-session.target \
    --property=KillMode=mixed \
    --property=TimeoutStopSec=5 \
    --setenv=PATH="$PATH" \
    hyprlock -q
