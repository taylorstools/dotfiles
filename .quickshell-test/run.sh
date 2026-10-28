#!/usr/bin/env bash
# Run the test Quickshell config in this folder.
#
#   ./run.sh            start the bar + launcher next to DMS (Ctrl+C to quit)
#   ./run.sh solo       same, but stop DMS while it runs and restart DMS after
#   ./run.sh launcher   toggle the launcher of the running instance
#   ./run.sh stop       stop a running instance
#
# Nothing here is installed or enabled anywhere; it only runs when you call it.

set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

qs_bin="$(command -v qs || command -v quickshell || true)"
if [[ -z "$qs_bin" ]]; then
    echo "quickshell isn't on PATH. Try: nix shell nixpkgs#quickshell -c $0 ${*:-}" >&2
    exit 1
fi

# DMS ships its Material Symbols font inside its own package instead of
# installing it, so find that copy for the bar's icons.
find_icon_font() {
    if fc-list : family 2>/dev/null | grep -q "Material Symbols Rounded"; then
        return 0
    fi
    local dms_bin root font
    dms_bin="$(command -v dms || true)"
    [[ -n "$dms_bin" ]] || return 0
    root="$(dirname "$(dirname "$(readlink -f "$dms_bin")")")"
    font="$(find -L "$root/share" -name 'MaterialSymbolsRounded*.ttf' -print -quit 2>/dev/null || true)"
    if [[ -n "$font" ]]; then
        export QSTEST_ICON_FONT="$font"
    else
        echo "warning: Material Symbols font not found; icons will show as text" >&2
    fi
}

case "${1:-start}" in
    start)
        find_icon_font
        exec "$qs_bin" -p "$dir"
        ;;
    solo)
        find_icon_font
        systemctl --user stop dms.service
        trap 'systemctl --user start dms.service' EXIT
        "$qs_bin" -p "$dir"
        ;;
    launcher)
        exec "$qs_bin" ipc -p "$dir" call launcher toggle
        ;;
    stop)
        exec "$qs_bin" kill -p "$dir"
        ;;
    *)
        sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
