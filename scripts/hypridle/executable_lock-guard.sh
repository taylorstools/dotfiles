#!/usr/bin/env bash

# Ends the session if the lock screen dies while the session is locked, as a
# killed or crashed hyprlock used to (its exit made lock_cmd's fallback quit
# niri). niri would keep the session locked on its own, and the restarted
# shell would lock again; this makes killing the lock screen cost the whole
# session instead, and greetd then starts a fresh one, locked.
#
# lock-session.sh starts it as the user unit lock-guard.service once the lock
# is up. It watches quickshell.service's main process and exits quietly once
# the lock screen's marker is gone (a normal unlock).
#
# LOCK_GUARD_UNIT and LOCK_GUARD_MARKER point it elsewhere, for testing.

set -uo pipefail

UNIT="${LOCK_GUARD_UNIT:-quickshell.service}"
MARKER="${LOCK_GUARD_MARKER:-$XDG_RUNTIME_DIR/qstest-locked.${WAYLAND_DISPLAY:-wayland}}"

PID=$(systemctl --user show -p MainPID --value "$UNIT")

quit() {
    echo "$1; ending the session"
    niri msg action quit --skip-confirmation
    exit 0
}

[[ -e "$MARKER" ]] || exit 0
[[ -n "$PID" && "$PID" != 0 ]] || quit "$UNIT has no running process while locked"

while [[ -e "$MARKER" ]]; do
    # Gone, or replaced by a restart: either way the lock screen that held
    # the lock is dead.
    if ! kill -0 "$PID" 2>/dev/null || [[ "$(systemctl --user show -p MainPID --value "$UNIT")" != "$PID" ]]; then
        quit "the lock screen ($UNIT, pid $PID) died while locked"
    fi
    sleep 0.25
done
