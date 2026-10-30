#!/usr/bin/env bash
#
# snipping-tool.sh: take a screenshot, copy it to the clipboard and say so in
# a notification. The notification has a "Save" button that opens a save
# dialog (Enter keeps the suggested name in ~/Pictures/Screenshots).
#
#   snipping-tool.sh            ask for the mode and delay in a yad dialog
#   snipping-tool.sh --region   go straight to region select, no dialog
#
# Window mode goes through niri's screenshot-window, which writes to the
# screenshot-path in niri's misc.kdl ($NiriShot below), so the two must match.

set -uo pipefail

NiriShot="/tmp/screenshot.png"
SaveDir="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Screenshots"
ShotDir="${XDG_RUNTIME_DIR:-/tmp}/snipping-tool"

#region Arguments
Mode=""
Wait=0

case "${1:-}" in
    --region) Mode="Region" ;;
    "") ;;
    *)
        echo "Usage: $(basename -- "$0") [--region]" >&2
        exit 2
        ;;
esac
#endregion

#region Mode dialog
if [ -z "$Mode" ]; then
    Values=$(yad \
        --title="Snipping Tool" \
        --form \
        --borders=30 \
        --field="<span size='x-large' weight='bold'>   Snipping Tool</span>:LBL" "" \
        --field=" :LBL" "" \
        --field="Mode:   :CB" "Region\!Window\!Screen" \
        --field="Delay:   :CB" "0\!1\!2\!3\!4\!5" \
        --separator="|" \
        --center \
        --width=350 \
        --height=260 \
        --button="Cancel:1" \
        --button="OK:0"
    ) 2>/dev/null || exit 0

    Mode=$(echo "$Values" | cut -d '|' -f 3)
    Wait=$(echo "$Values" | cut -d '|' -f 4)
fi
#endregion

#region Capture
mkdir -p "$ShotDir"
# Its own file per screenshot, so a second one taken while this notification
# is still up doesn't replace the image its Save button would save.
ShotFile=$(mktemp "$ShotDir/screenshot-XXXXXX.png")
Stamp=$(date +%Y-%m-%d_%H-%M-%S)
trap 'rm -f "$ShotFile"' EXIT

[ -n "$Wait" ] && [ "$Wait" -gt 0 ] && sleep "$Wait"

case "$Mode" in
    Region)
        # Esc in slurp cancels the whole thing.
        Geometry=$(slurp) || exit 0
        grim -g "$Geometry" "$ShotFile" || exit 1
        ;;
    Screen)
        grim "$ShotFile" || exit 1
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
        mv -f "$NiriShot" "$ShotFile"
        ;;
    *)
        exit 1
        ;;
esac
#endregion

#region Clipboard
# wl-copy forks and keeps serving the image after this script exits.
wl-copy --type image/png < "$ShotFile"
#endregion

#region Notification
# Blocks until the notification is answered or closed. The shell also runs the first
# action when the notification body is clicked, so that saves too.
Action=$(notify-send \
    --app-name="Snipping Tool" \
    --icon="$ShotFile" \
    --action=save="Save" \
    --wait \
    "Screenshot copied to clipboard" 2>/dev/null || true)

[ "$Action" = "save" ] || exit 0
#endregion

#region Save
mkdir -p "$SaveDir"

Target=$(yad \
    --title="Save Screenshot" \
    --file \
    --save \
    --confirm-overwrite \
    --add-preview \
    --filename="$SaveDir/Screenshot_$Stamp.png" \
    --file-filter="PNG images | *.png" \
    --center \
    --width=900 \
    --height=600 \
    2>/dev/null) || exit 0

[ -n "$Target" ] || exit 0
case "$Target" in
    *.png | *.PNG) ;;
    *) Target="$Target.png" ;;
esac

# Only a failed save gets a notification.
if ! cp -f "$ShotFile" "$Target"; then
    notify-send --app-name="Snipping Tool" --urgency=critical --icon=dialog-error \
        "Couldn't save screenshot" "$Target"
fi
#endregion
