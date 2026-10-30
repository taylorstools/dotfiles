#!/usr/bin/env bash
#
# Pick a colour anywhere on screen with niri's own picker, copy its hex code
# and say which it was.

set -uo pipefail

out=$(niri msg pick-color 2>/dev/null) || exit 0
hex=$(grep -oiE '#[0-9a-f]{6}' <<<"$out" | head -n1)
[[ -n $hex ]] || exit 0   # Esc cancels the pick

printf '%s' "$hex" | wl-copy
