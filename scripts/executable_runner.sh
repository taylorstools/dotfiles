#!/usr/bin/env bash
#
# runner.sh: a Win+R-style launcher (fzf in a floating kitty window).
#
# The prompt is the folder you're in, and what you type filters its entries.
#
#   Up/Down         move through the entries
#   Right / Tab     complete: step into the highlighted folder, or put the
#                   highlighted file's name in the field
#   Backspace       on an empty field, go up one folder
#   typing /, ~, .. jump there directly (paste a full path and it works too)
#   Enter           open, never run: folders in Thunar, files in their default
#                   app (so a script opens in your editor). With nothing
#                   highlighted, open what you typed as a path or URL
#   Alt+Enter       run: what you typed, if it starts with a command on your
#                   PATH; otherwise the highlighted program or script (from its
#                   own folder); otherwise what you typed, as a shell command
#   Ctrl+F          search recursively below this folder (press again to go back)
#   Ctrl+A          clear the field (back to / with nothing typed)
#   Ctrl+C          copy the highlighted path (or what you typed) and close
#   Esc             close
#
# Run it with no arguments and it toggles: it opens the window, or closes it if
# it's already open. The check happens before a terminal is spawned, so
# closing it doesn't flash a second window.

set -uo pipefail

Self=$(realpath -- "${BASH_SOURCE[0]}")
PidFile="${XDG_RUNTIME_DIR:-/tmp}/runner.sh.pid"
ColorsFile="$HOME/.config/matugen/colors.conf"
export Self

# Launch a program fully detached from this terminal. Under niri, the
# compositor spawns it, so it gets focus and outlives the runner window.
spawn() {
    if [[ -n ${NIRI_SOCKET:-} ]] && niri msg action spawn -- "$@" >/dev/null 2>&1; then
        return
    fi
    # Fallback: ignore SIGHUP (inherited through fork/exec, like nohup) so the
    # child survives kitty closing the pty.
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

# Open in the default app: folders in Thunar, files with xdg-open.
open_path() {
    if [[ -d $1 ]]; then
        spawn thunar "$1"
    else
        spawn xdg-open "$1"
    fi
}

# Run a program or script from its own folder.
run_file() {
    spawn sh -c 'cd -- "$(dirname -- "$1")" && exec "$1"' sh "$1"
}

copy_text() {
    if command -v wl-copy >/dev/null; then
        spawn wl-copy -- "$1"
    else
        printf '%s' "$1" | xclip -selection clipboard
    fi
}

# fzf action "name(arg)", picking a delimiter pair that doesn't occur in arg,
# so paths containing ")" can't break the action string.
act() {
    local pair
    for pair in '()' '[]' '{}' '<>' '~~' '!!' '@@' '##' '%%' '^^' '&&' ';;' '||'; do
        if [[ $2 != *"${pair:1:1}"* ]]; then
            printf '%s%s%s%s' "$1" "${pair:0:1}" "$2" "${pair:1:1}"
            return
        fi
    done
}

# The prompt is the current folder, with a trailing "**/" in search mode.
in_search() { [[ $FZF_PROMPT == *'**/' ]]; }
cur_dir() { printf '%s' "${FZF_PROMPT%'**/'}"; }

# Resolve typed text against the current folder: /abs, ~, ~/x, or relative.
resolve() {
    # shellcheck disable=SC2088  # matching a literal "~" on purpose
    case $1 in
        /*)   printf '%s' "$1" ;;
        '~')  printf '%s/' "$HOME" ;;
        '~/'*) printf '%s/%s' "$HOME" "${1#'~/'}" ;;
        *)    printf '%s%s' "$(cur_dir)" "$1" ;;
    esac
}

is_url() { [[ $1 =~ ^[A-Za-z][A-Za-z0-9+.-]*:// ]]; }

#region List producers (fed to fzf as "full path<TAB>display")

# One folder: visible folders, visible files, hidden folders, hidden files.
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

# Everything below a folder (fd honors .gitignore/.ignore/.fdignore).
search_dir() {
    local dir=${1%'**/'}
    fd --hidden --exclude .git --type f --type d --color never \
        --base-directory "$dir" . 2>/dev/null |
        awk -v dir="$dir" 'BEGIN { OFS = "\t" } { print dir $0, $0 }'
}

#endregion

#region fzf event handlers (each prints the fzf actions to run)

# Show folder $1 (trailing slash) with $2 in the query.
nav() {
    act change-prompt "$1"
    printf '+'
    act change-query "${2-}"
    printf '+reload(list_dir "$FZF_PROMPT")+first'
}

# Query changed: if it now holds a path to an existing folder, move that
# folder into the prompt and keep only the part after the last slash.
on_change() {
    local q=$FZF_QUERY target dir
    in_search && return
    [[ $q == */* ]] || return
    is_url "$q" && return
    target=$(resolve "$q")
    dir=$(realpath -ms -- "${target%/*}/") || return
    [[ -d $dir ]] || return
    [[ $dir == / ]] || dir+=/
    nav "$dir" "${target##*/}"
}

# Right/Tab: step into the highlighted folder, or complete the file's name.
on_complete() {
    local path=${1-}
    if [[ -z $path ]]; then
        printf 'forward-char'
    elif [[ -d $path ]]; then
        nav "${path%/}/"
    else
        nav "$(dirname -- "$path")/" "$(basename -- "$path")"
    fi
}

# Backspace on an empty query: leave search mode, or go up one folder.
on_back() {
    local dir
    dir=$(cur_dir)
    if in_search; then
        nav "$dir"
    elif [[ $dir != / ]]; then
        dir=$(dirname -- "$dir")
        [[ $dir == / ]] || dir+=/
        nav "$dir"
    fi
}

on_search_toggle() {
    local dir
    dir=$(cur_dir)
    if in_search; then
        nav "$dir" "$FZF_QUERY"
    else
        act change-prompt "$dir**/"
        printf '+reload(search_dir "$FZF_PROMPT")+first'
    fi
}

# Enter. With a match, hand it back to the main script. With none, open the
# typed text as a URL or path.
on_enter() {
    local q=$FZF_QUERY target
    if (( FZF_MATCH_COUNT > 0 )); then
        printf 'accept'
        return
    fi
    [[ -n $q ]] || return
    target=$(resolve "$q")
    if is_url "$q"; then
        spawn xdg-open "$q"
    elif [[ -e $target ]]; then
        open_path "$target"
    else
        act change-border-label " Nothing matches: $q (alt-⏎ to run it) "
        return
    fi
    printf 'abort'
}

# Alt+Enter. Typed text that starts with a real command (firefox, git pull)
# wins, so a fuzzy match can't hijack it; otherwise run the highlighted
# program or script; otherwise run the typed text as a shell command.
on_run() {
    local path=${1-} q=$FZF_QUERY
    if [[ -n $q ]] && command -v -- "${q%% *}" >/dev/null; then
        run_in "$(cur_dir)" "$q"
    elif [[ -n $path ]] && is_program "$path"; then
        run_file "$path"
    elif [[ -n $q ]]; then
        run_in "$(cur_dir)" "$q"
    else
        return
    fi
    printf 'abort'
}

on_copy() {
    local text=${1-}
    [[ -n $text ]] || text=$(resolve "$FZF_QUERY")
    copy_text "$text"
    printf 'abort'
}

#endregion

#region Main

run_ui() {
    echo $$ >"$PidFile"
    trap 'rm -f "$PidFile"' EXIT

    # Theme colors from matugen, e.g. "$light = rgba(51606fff)".
    local light="#51606f" lighter="#b9c8da" line
    local re='^\$(light|lighter)[[:space:]]*=[[:space:]]*rgba?\(([0-9A-Fa-f]{6})'
    if [[ -r $ColorsFile ]]; then
        while IFS= read -r line; do
            [[ $line =~ $re ]] || continue
            case ${BASH_REMATCH[1]} in
                light) light="#${BASH_REMATCH[2]}" ;;
                lighter) lighter="#${BASH_REMATCH[2]}" ;;
            esac
        done <"$ColorsFile"
    fi

    export -f spawn run_in is_program open_path run_file copy_text act in_search cur_dir resolve is_url \
        list_dir search_dir nav on_change on_complete on_back \
        on_search_toggle on_enter on_run on_copy

    local hint=" → into · ⌫ up · ^F search · alt-⏎ run · ^A clear · ^C copy "
    local selected
    selected=$(
        list_dir "$HOME/" |
            fzf \
                --with-shell 'bash -c' \
                --delimiter '\t' --with-nth 2 \
                --scheme path \
                --prompt "$HOME/" \
                --layout reverse --info hidden --cycle \
                --border --border-label "$hint" --border-label-pos 0:bottom \
                --bind "change:change-border-label($hint)+transform:on_change" \
                --bind 'right:transform:on_complete {1}' \
                --bind 'tab:transform:on_complete {1}' \
                --bind 'backward-eof:transform:on_back' \
                --bind 'ctrl-f:transform:on_search_toggle' \
                --bind 'enter:transform:on_enter' \
                --bind 'alt-enter:transform:on_run {1}' \
                --bind 'ctrl-a:transform:nav /' \
                --bind 'ctrl-c:transform:on_copy {1}' \
                --color "
                    fg:#ffffff, query:#ffffff,
                    fg+:$lighter, prompt:$lighter, hl:$lighter, hl+:#ffffff,
                    pointer:$lighter, selected-fg:$lighter, selected-bg:#000000,
                    bg:#000000, bg+:$light, list-bg:#000000, gutter:#000000,
                    border:$light, label:$light
                "
    )

    [[ -n $selected ]] && open_path "${selected%%$'\t'*}"
}

# Toggle: close the open runner (if its PID is still a runner), else launch.
toggle() {
    local pid
    if [[ -r $PidFile ]] && read -r pid <"$PidFile" && [[ $pid =~ ^[0-9]+$ ]] &&
        grep -qF "$Self" "/proc/$pid/cmdline" 2>/dev/null; then
        kill -- "-$pid" 2>/dev/null || kill "$pid"
        exit 0
    fi
    # Your kitty.conf maps ctrl+c to copy; in this window pass it to fzf.
    exec kitty --title Runner -o "map ctrl+c no_op" "$Self" --ui
}

if [[ ${1-} == --ui ]]; then
    run_ui
else
    toggle
fi

#endregion
