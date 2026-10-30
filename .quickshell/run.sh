#!/usr/bin/env bash
# Work on the shell. It normally runs as the quickshell.service user unit
# (dot_config/systemd/user/quickshell.service); this runs it by hand instead.
#
#   ./run.sh            stop the service, run here with errors in the terminal
#                       (Ctrl+C to quit), start the service again after
#   ./run.sh restart    restart the service
#   ./run.sh logs       follow the service's log
#   ./run.sh launcher   toggle the launcher of the running instance
#   ./run.sh runner     toggle the runner (Win+R) of the running instance
#   ./run.sh clipboard  toggle the clipboard history of the running instance
#   ./run.sh notepad    toggle the notepad of the running instance
#   ./run.sh settings   toggle the settings window of the running instance
#   ./run.sh stop       stop a running instance

set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

qs_bin="$(command -v qs || command -v quickshell || true)"
if [[ -z "$qs_bin" ]]; then
    echo "quickshell isn't on PATH. Try: nix shell nixpkgs#quickshell -c $0 ${*:-}" >&2
    exit 1
fi

case "${1:-start}" in
    start)
        systemctl --user stop quickshell.service 2>/dev/null || true
        trap 'systemctl --user start quickshell.service' EXIT
        "$qs_bin" -p "$dir"
        ;;
    restart)
        exec systemctl --user restart quickshell.service
        ;;
    logs)
        exec journalctl --user -fu quickshell.service
        ;;
    launcher)
        exec "$qs_bin" ipc -p "$dir" call launcher toggle
        ;;
    notepad)
        exec "$qs_bin" ipc -p "$dir" call notepad toggle
        ;;
    runner)
        exec "$qs_bin" ipc -p "$dir" call runner toggle
        ;;
    clipboard)
        exec "$qs_bin" ipc -p "$dir" call clipboard toggle
        ;;
    settings)
        exec "$qs_bin" ipc -p "$dir" call settings toggle
        ;;
    stop)
        exec "$qs_bin" kill -p "$dir"
        ;;
    *)
        sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
