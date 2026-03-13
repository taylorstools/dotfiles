#!/usr/bin/env bash

OUT="/tmp/screenshot.png"

values=$(yad \
    --title="Snipping Tool" \
    --form \
    --markup \
    --borders=30 \
    --field="<span size='x-large' weight='bold'>   Snipping Tool</span>:LBL" "" \
    --field=" :LBL" "" \
    --field="Mode:   :CB" "Region\!Window\!Screen" \
    --field="Delay:   :CB" "0\!1\!2\!3\!4\!5" \
    --separator="|" \
    --center \
    --width=350 \
    --height=260 \
    --button="Cancel:1" \
    --button="OK:0"
) 2>/dev/null

result=$?

# Cancel
[ "$result" -ne 0 ] && exit 0

mode=$(echo "$values" | cut -d '|' -f 3)
wait=$(echo "$values" | cut -d '|' -f 4)

# Delay
[ -n "$wait" ] && sleep "$wait"

rm -f "$OUT"

case "$mode" in
    Region)
        grim -g "$(slurp)" "$OUT"
        ;;
    Screen)
        grim "$OUT"
        ;;
    Window)
        # compositor-privileged capture
        niri msg action screenshot-window
        ;;
    *)
        exit 1
        ;;
esac

# Wait for niri to write the file (window mode)
while [ ! -f "$OUT" ]; do
    sleep 0.05
done

satty -f "$OUT" --disable-notifications