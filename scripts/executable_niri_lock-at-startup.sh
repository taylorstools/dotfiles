#!/usr/bin/env bash

# Brings the session up locked, but not on the first session after a boot -
# that one is already authenticated by the Plymouth LUKS prompt.
#
# greetd runs initial_session exactly once per boot and default_session for
# every session after it, and default_session is the one that sets
# NIRI_LOCK_AT_STARTUP=1. See nixos/modules/components/greetd.nix.
#
# The uptime check below is a second, fail-closed test: a session that starts
# without the marker long after boot is a re-login whose marker went missing,
# not a cold boot, so it locks anyway. The failure mode of a wrong guess here
# should be an unnecessary lock screen, never an unlocked desktop.
#
# Logs to ~/.local/state/niri-lock-at-startup.log, which survives a reboot.

set -uo pipefail

TAG="niri-lock-at-startup"
LOGFILE="${XDG_STATE_HOME:-$HOME/.local/state}/niri-lock-at-startup.log"
FAILURESTAMP="${XDG_CACHE_HOME:-$HOME/.cache}/niri-lock-at-startup.last-failure"
COLDBOOTGRACE=180   # seconds; a markerless session older than this still locks
RETRYWINDOW=120     # seconds; a second failure inside this window stops retrying

UPTIME=$(cut -d. -f1 /proc/uptime)

mkdir -p "$(dirname "$LOGFILE")"

# Keep the log from growing without bound across many sessions.
if [[ -f "$LOGFILE" ]] && (( $(wc -l < "$LOGFILE") > 3000 )); then
    tail -n 1000 "$LOGFILE" > "$LOGFILE.trimmed" && mv "$LOGFILE.trimmed" "$LOGFILE"
fi

log() {
    printf "%s  %s\n" "$(date "+%H:%M:%S")" "$*" >> "$LOGFILE"
    echo "$TAG: $*"
}

log "=== session start  uptime=${UPTIME}s  logind-session=${XDG_SESSION_ID:-unset}  display=${WAYLAND_DISPLAY:-unset}  NIRI_LOCK_AT_STARTUP=${NIRI_LOCK_AT_STARTUP:-unset}"

if [[ "${NIRI_LOCK_AT_STARTUP:-0}" == 1 ]]; then
    log "greetd default_session: locking"
elif (( UPTIME < COLDBOOTGRACE )); then
    log "first session ${UPTIME}s into this boot: LUKS already authenticated, leaving it unlocked"
    exit 0
else
    log "no marker but ${UPTIME}s into this boot, so this is a re-login: locking anyway"
fi

if pgrep -x hyprlock >/dev/null; then
    log "hyprlock is ALREADY RUNNING (pids: $(pgrep -x hyprlock | tr "\n" " ")), not starting another"
    exit 0
fi

# Not -q: hyprlock's own output goes to the log, which is where it is wanted
# if this ever fails again.
hyprlock >> "$LOGFILE" 2>&1
STATUS=$?
log "hyprlock exited with status $STATUS"

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
    log "hyprlock also failed $((NOW - LAST))s ago; leaving this session unlocked rather than looping"
    exit 1
fi

mkdir -p "$(dirname "$FAILURESTAMP")"
echo "$NOW" > "$FAILURESTAMP"
log "quitting niri so greetd starts a fresh session and we try again"
niri msg action quit --skip-confirmation
