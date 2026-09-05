#!/usr/bin/env bash

# Brings the session up locked, but only when this niri session is a re-login
# rather than the first one since boot.
#
# A cold boot is already authenticated by the Plymouth LUKS prompt, so it goes
# straight to the desktop. greetd runs initial_session exactly once per boot
# and default_session for every session after it, which is every logout -
# default_session is the one that sets NIRI_LOCK_AT_STARTUP=1.
# See nixos/modules/components/greetd.nix.
#
# If hyprlock will not start, quit niri rather than leave an unlocked desktop
# sitting there; greetd starts a fresh session and this runs again.

set -euo pipefail

if [[ "${NIRI_LOCK_AT_STARTUP:-0}" != 1 ]]; then
    exit 0
fi

if pgrep -x hyprlock >/dev/null; then
    exit 0
fi

# Blocks until unlocked. Non-zero means hyprlock never got a lock surface up.
if ! hyprlock -q; then
    echo "hyprlock failed to start, quitting niri"
    niri msg action quit --skip-confirmation
fi
