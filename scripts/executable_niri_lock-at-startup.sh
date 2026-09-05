#!/usr/bin/env bash

# Brings the session up locked, but not on the first session after a boot -
# that one is already authenticated by the Plymouth LUKS prompt.
#
# greetd runs initial_session exactly once per boot and default_session for
# every session after it, and default_session is the one that sets
# NIRI_LOCK_AT_STARTUP=1. See nixos/modules/components/greetd.nix.
#
# The uptime check is a second, fail-closed test: a session that starts
# without the marker long after boot is a re-login whose marker went missing,
# not a cold boot, so it locks anyway. A wrong guess here should cost an
# unnecessary lock screen, never an unlocked desktop.
#
# Output goes to the niri journal: journalctl --user -b -u niri.service

set -uo pipefail

FAILURESTAMP="${XDG_CACHE_HOME:-$HOME/.cache}/niri-lock-at-startup.last-failure"
COLDBOOTGRACE=180   # seconds; a markerless session older than this still locks
RETRYWINDOW=120     # seconds; a second failure inside this window stops retrying

UPTIME=$(cut -d. -f1 /proc/uptime)

if [[ "${NIRI_LOCK_AT_STARTUP:-0}" != 1 ]] && (( UPTIME < COLDBOOTGRACE )); then
    exit 0
fi

if pgrep -x hyprlock >/dev/null; then
    exit 0
fi

hyprlock -q
STATUS=$?

if (( STATUS == 0 )); then
    rm -f "$FAILURESTAMP"
    exit 0
fi

# hyprlock never got a lock surface up. Quitting niri hands greetd a fresh
# session to try again - but only if the last failure was a while ago. A
# hyprlock that is broken rather than unlucky would otherwise quit niri over
# and over with nothing on screen to say so.
NOW=$(date +%s)
LAST=0
[[ -r "$FAILURESTAMP" ]] && LAST=$(<"$FAILURESTAMP")

if (( NOW - LAST < RETRYWINDOW )); then
    echo "hyprlock exited $STATUS, and also failed $((NOW - LAST))s ago; leaving this session unlocked rather than looping"
    exit 1
fi

mkdir -p "$(dirname "$FAILURESTAMP")"
echo "$NOW" > "$FAILURESTAMP"
echo "hyprlock exited $STATUS; quitting niri so greetd starts a fresh session"
niri msg action quit --skip-confirmation
