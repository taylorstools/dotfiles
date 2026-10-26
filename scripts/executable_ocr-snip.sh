#!/usr/bin/env bash
#
# ocr-snip.sh: select a region, OCR it with tesseract, copy the text to the
# clipboard and show it in a notification.

set -uo pipefail

#region Capture and OCR
# Esc in slurp cancels the whole thing.
Geometry=$(slurp) || exit 0

# -s 2 captures at double scale; tesseract is much more accurate on small UI text.
Text=$(grim -s 2 -g "$Geometry" - | tesseract stdin stdout --psm 6 2>/dev/null)
Text="${Text%"${Text##*[![:space:]]}"}" # trim trailing whitespace/newlines
#endregion

#region Clipboard and notification
if [ -z "$Text" ]; then
    notify-send --app-name="OCR" --icon=dialog-warning "No text found"
    exit 0
fi

printf "%s" "$Text" | wl-copy
notify-send --app-name="OCR" "Text copied to clipboard"
#endregion
