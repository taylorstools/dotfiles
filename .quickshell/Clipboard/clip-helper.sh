#!/usr/bin/env bash
#
# Shell side of the clipboard history (Services/ClipboardHistory.qml).
#
#   clip-helper.sh capture DIR        run by `wl-paste --watch` on every copy:
#                                     saves the new clipboard to DIR and prints
#                                     "id<TAB>kind<TAB>hash<TAB>bytes<TAB>preview"
#   clip-helper.sh copy FILE KIND     put a saved entry back on the clipboard
#   clip-helper.sh paste TERMINAL     type Ctrl+V (Ctrl+Shift+V if TERMINAL is 1)
#                                     into the focused window with wtype
#   clip-helper.sh method             "wtype", or "none" if it isn't installed
#
# Entries are DIR/<id>.txt or DIR/<id>.png.

set -uo pipefail

MAX_BYTES=$((5 * 1024 * 1024)) # largest entry kept

capture() {
    local dir=$1 types id file kind bytes hash preview
    # wl-paste pipes the content in; it's fetched again below by type.
    cat >/dev/null
    # Password managers mark their copies sensitive; never store those.
    case ${CLIPBOARD_STATE:-data} in
        sensitive | nil | clear) return 0 ;;
    esac
    types=$(wl-paste --list-types 2>/dev/null) || return 0
    mkdir -p "$dir"
    id=$(date +%s%N)
    if grep -q '^text/' <<<"$types" || grep -qx 'UTF8_STRING\|STRING\|TEXT' <<<"$types"; then
        kind=text
        file=$dir/$id.txt
        wl-paste --no-newline --type text >"$file" 2>/dev/null || true
    elif grep -qx 'image/png' <<<"$types"; then
        kind=image
        file=$dir/$id.png
        wl-paste --type image/png >"$file" 2>/dev/null || true
    else
        return 0
    fi
    bytes=$(stat -c %s "$file" 2>/dev/null || echo 0)
    if ((bytes == 0 || bytes > MAX_BYTES)); then
        rm -f "$file"
        return 0
    fi
    hash=$(sha1sum "$file" | cut -c1-40)
    preview=""
    if [[ $kind == text ]]; then
        # One line for the list; the QML trims it to length.
        preview=$(head -c 1500 "$file" | tr '\n\r\t' '   ')
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$kind" "$hash" "$bytes" "$preview"
}

case ${1-} in
    capture)
        capture "$2"
        ;;
    copy)
        if [[ $3 == image ]]; then
            wl-copy --type image/png <"$2"
        else
            wl-copy <"$2"
        fi
        ;;
    paste)
        # wtype types through the Wayland virtual-keyboard protocol, which
        # niri supports. Without it the entry is only copied.
        command -v wtype >/dev/null || exit 3
        if [[ ${2-0} == 1 ]]; then
            wtype -M ctrl -M shift v -m shift -m ctrl
        else
            wtype -M ctrl v -m ctrl
        fi
        ;;
    method)
        if command -v wtype >/dev/null; then echo wtype; else echo none; fi
        ;;
    *)
        sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
        exit 2
        ;;
esac
