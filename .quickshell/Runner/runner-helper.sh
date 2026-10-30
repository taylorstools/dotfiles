#!/usr/bin/env bash
#
# Shell side of Runner.qml: the parts of ~/scripts/runner.sh that were easier
# to keep as they are than to redo in QML. Runner.qml calls it as
# `bash runner-helper.sh <command> ...`.
#
#   list-dir DIR          DIR's entries: folders, files, hidden folders, hidden files
#   list-below DIR        everything in DIR's subfolders
#   dir PATH              PATH resolved, with a trailing slash, if it's a folder
#   kind PATH             dir, editor, editor-choice, other or missing
#   run DIR QUERY PATH    the Alt+Enter rules, launched detached
#
# The list commands print "full path<TAB>display" lines, folders ending in /.

set -uo pipefail

# Launch a program fully detached. Under niri the compositor spawns it, so it
# gets focus and outlives the shell.
spawn() {
    if [[ -n ${NIRI_SOCKET:-} ]] && niri msg action spawn -- "$@" >/dev/null 2>&1; then
        return
    fi
    (trap '' HUP; setsid -f "$@" </dev/null >/dev/null 2>&1)
}

# Run a shell command line from folder $1, detached.
run_in() {
    spawn sh -c 'cd -- "$1" || exit; exec sh -c "$2"' sh "$1" "$2"
}

# A file to run rather than open: executable, and a script (#!) or an ELF
# binary. The content check keeps files that are merely +x (anything on an
# exFAT/NTFS drive, say) opening normally.
is_program() {
    local magic
    [[ -f $1 && -x $1 ]] || return 1
    IFS= read -r -n 4 magic <"$1" 2>/dev/null
    [[ $magic == '#!'* || $magic == $'\x7fELF' ]]
}

# Run a program or script from its own folder.
run_file() {
    spawn sh -c 'cd -- "$(dirname -- "$1")" && exec "$1"' sh "$1"
}

list_dir() {
    local dir=$1
    [[ $dir == */ ]] || dir+=/
    find -L "$dir" -mindepth 1 -maxdepth 1 -printf '%y\t%f\n' 2>/dev/null |
        awk -F'\t' -v dir="$dir" 'BEGIN { OFS = "\t" } {
            name = $2
            if ($1 == "d") name = name "/"
            rank = (substr(name, 1, 1) == ".") * 2 + ($1 != "d")
            print rank, tolower(name), dir name, name
        }' |
        LC_ALL=C sort -t$'\t' -k1,1n -k2,2 |
        cut -f3-
}

# Depth 2 and deeper, since list_dir already covers depth 1. Skips .git,
# .cache and node_modules (plus /nix, /proc, /sys, /dev and /run from /) and
# honors .gitignore, .ignore and ~/.config/fd/ignore.
list_below() {
    local dir=$1
    [[ $dir == */ ]] || dir+=/
    local -a skip=(--exclude .git --exclude .cache --exclude node_modules)
    if [[ $dir == / ]]; then
        skip+=(--exclude /nix --exclude /proc --exclude /sys --exclude /dev --exclude /run)
    fi
    fd --hidden --min-depth 2 --type f --type d --color never "${skip[@]}" \
        --base-directory "$dir" . 2>/dev/null |
        awk -v dir="$dir" 'BEGIN { OFS = "\t" } { print dir $0, $0 }'
}

# The app the user's own mimeapps.list sets as default for a MIME type, if any.
user_default_app() {
    local list="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"
    [[ -r $list ]] || return 0
    awk -F= -v mime="$1" '
        /^\[/ { in_defaults = ($0 == "[Default Applications]"); next }
        in_defaults && $1 == mime { split($2, apps, ";"); print apps[1]; exit }
    ' "$list"
}

# Plain text: no NUL bytes in the first 8 KiB (an empty file counts as text).
is_text() {
    local all stripped
    all=$(head -c 8192 -- "$1" | wc -c)
    stripped=$(head -c 8192 -- "$1" | tr -d '\000' | wc -c)
    (( all == stripped ))
}

# A file for a text editor: its type is mapped to xed in mimeapps.list, or it
# isn't mapped at all and its contents are plain text. Deciding by content
# covers types the MIME database names oddly or not at all (.kdl, say), which
# xdg-open would otherwise hand to a web browser as a last resort.
opens_in_xed() {
    local mime="" app=""
    [[ -f $1 && -r $1 ]] || return 1
    if command -v xdg-mime >/dev/null; then
        mime=$(xdg-mime query filetype "$1" 2>/dev/null)
    fi
    [[ -n $mime ]] && app=$(user_default_app "$mime")
    if [[ -n $app ]]; then
        [[ $app == org.x.editor.desktop ]]
    else
        is_text "$1"
    fi
}

case ${1-} in
    list-dir)
        list_dir "$2"
        ;;
    list-below)
        list_below "$2"
        ;;
    dir)
        d=$(realpath -ms -- "$2") && [[ -d $d ]] || exit 1
        [[ $d == / ]] || d+=/
        printf '%s' "$d"
        ;;
    kind)
        if [[ ! -e $2 ]]; then
            echo missing
        elif [[ -d $2 ]]; then
            echo dir
        elif opens_in_xed "$2"; then
            # Ask xed or VSCodium only where VSCodium is installed.
            if command -v codium >/dev/null; then echo editor-choice; else echo editor; fi
        else
            echo other
        fi
        ;;
    run)
        # Typed text that starts with a real command (firefox, git pull) wins,
        # so a fuzzy match can't hijack it; otherwise run the highlighted
        # program or script; otherwise run the typed text as a shell command.
        dir=$2 query=$3 path=${4-}
        if [[ -n $query ]] && command -v -- "${query%% *}" >/dev/null; then
            run_in "$dir" "$query"
        elif [[ -n $path ]] && is_program "$path"; then
            run_file "$path"
        elif [[ -n $query ]]; then
            run_in "$dir" "$query"
        else
            exit 1
        fi
        ;;
    *)
        sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
        exit 2
        ;;
esac
