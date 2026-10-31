#!/usr/bin/env bash
#
# The shell parts of the snipping tool (SnippingTool.qml), from the old
# scripts/snipping-tool.sh.
#
#   snip-helper.sh capture Region|Window|Screen FILE
#       Exit 0 with the screenshot in FILE, 2 if Esc cancelled the region
#       select, 1 if it failed.
#
# Window mode goes through niri's screenshot-window, which writes to the
# screenshot-path in niri's misc.kdl ($NiriShot below), so the two must match.

set -uo pipefail

NiriShot="/tmp/screenshot.png"

[ "${1:-}" = capture ] || { echo "usage: $0 capture MODE FILE" >&2; exit 1; }
Mode="${2:-}"
File="${3:-}"
[ -n "$File" ] || exit 1
mkdir -p "$(dirname -- "$File")"

case "$Mode" in
    Region)
        # Esc in slurp cancels the whole thing. Its stdin must be empty: slurp
        # reads boxes to choose from when stdin isn't a terminal, and the
        # shell's pipe never closes, so it would wait there forever.
        Geometry=$(slurp </dev/null) || exit 2
        grim -g "$Geometry" "$File" || exit 1
        ;;
    Screen)
        grim "$File" || exit 1
        ;;
    Window)
        # compositor-privileged capture, written to niri's screenshot-path
        rm -f "$NiriShot"
        niri msg action screenshot-window || exit 1
        for _ in $(seq 100); do
            [ -s "$NiriShot" ] && break
            sleep 0.05
        done
        [ -s "$NiriShot" ] || { echo "niri didn't write $NiriShot" >&2; exit 1; }
        # Let niri finish writing before taking the file.
        sleep 0.1
        mv -f "$NiriShot" "$File"
        ;;
    *)
        exit 1
        ;;
esac
