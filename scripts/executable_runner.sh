#!/usr/bin/env bash
#
# runner.sh: a Win+R-style launcher (fzf in a floating kitty window).
#
# The prompt is the folder you're in. What you type fuzzy-finds everything
# below it: the folder's own entries are listed first, then everything in its
# subfolders.
#
#   Up/Down         move through the entries
#   Right / Tab     complete: step into the highlighted folder, or put the
#                   highlighted file's name in the field
#   Backspace       on an empty field, go up one folder
#   typing /, ~, .. jump there directly (paste a full path and it works too)
#   Enter           open, never run: folders in Thunar, files in their default
#                   app. Anything that would open in xed asks whether to use
#                   xed or VSCodium (when VSCodium is installed). With nothing
#                   highlighted, open what you typed as a path or URL
#   Alt+Enter       run: what you typed, if it starts with a command on your
#                   PATH; otherwise the highlighted program or script (from its
#                   own folder); otherwise what you typed, as a shell command
#   Ctrl+F          switch between "everything below" and "this folder only"
#   Ctrl+A          clear the field (back to / with nothing typed)
#   Ctrl+C          copy the highlighted path (or what you typed) and close
#   Esc             close
#
# Run it with no arguments and it toggles: it opens the window, or closes it if
# it's already open. The check happens before a terminal is spawned, so
# closing it doesn't flash a second window.
#
# The recursive search skips .git, .cache and node_modules (plus /nix, /proc,
# /sys, /dev and /run when searching from /) and honors .gitignore, .ignore
# and ~/.config/fd/ignore. Step into an excluded folder to search inside it.

set -uo pipefail

Self=$(realpath -- "${BASH_SOURCE[0]}")
PidFile="${XDG_RUNTIME_DIR:-/tmp}/runner.sh.pid"
ColorsFile="$HOME/.config/matugen/colors.conf"
export Self

#region Helpers

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

# The prompt is always the current folder, with a trailing slash.
cur_dir() { printf '%s' "$FZF_PROMPT"; }

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

# Search mode lives in a file so every handler sees it: "tree" (the default,
# everything below) or "flat" (this folder only).
get_mode() {
    local mode=tree
    [[ -r $StateDir/mode ]] && read -r mode <"$StateDir/mode"
    printf '%s' "$mode"
}

# The key hints along the bottom border, per mode.
label() {
    if [[ $(get_mode) == flat ]]; then
        printf '%s' " this folder only · ^F search subfolders too · → into · ⌫ up · alt-⏎ run "
    else
        printf '%s' " → into · ⌫ up · ^F this folder only · alt-⏎ run · ^A clear · ^C copy "
    fi
}

#endregion

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

# Everything in the subfolders of a folder (depth 2 and deeper, since
# list_dir already covers depth 1). Displayed relative to the folder.
list_below() {
    local dir=$1
    local -a skip=(--exclude .git --exclude .cache --exclude node_modules)
    if [[ $dir == / ]]; then
        skip+=(--exclude /nix --exclude /proc --exclude /sys --exclude /dev --exclude /run)
    fi
    fd --hidden --min-depth 2 --type f --type d --color never "${skip[@]}" \
        --base-directory "$dir" . 2>/dev/null |
        awk -v dir="$dir" 'BEGIN { OFS = "\t" } { print dir $0, $0 }'
}

# What fzf shows for a folder: its entries first, then (in tree mode) the rest.
load() {
    local dir=$1
    [[ $dir == */ ]] || dir+=/
    list_dir "$dir"
    [[ $(get_mode) == flat ]] || list_below "$dir"
}

#endregion

#region fzf event handlers (each prints the fzf actions to run)

# Show folder $1 (trailing slash) with $2 in the query.
nav() {
    act change-prompt "$1"
    printf '+'
    act change-query "${2-}"
    printf '+reload(load "$FZF_PROMPT")+first'
}

# Query changed: reset the hint line, and if the query now holds a path to an
# existing folder, move that folder into the prompt and keep only the part
# after the last slash.
on_change() {
    local q=$FZF_QUERY target dir
    act change-border-label "$(label)"
    [[ $q == */* ]] || return
    is_url "$q" && return
    target=$(resolve "$q")
    dir=$(realpath -ms -- "${target%/*}/") || return
    [[ -d $dir ]] || return
    [[ $dir == / ]] || dir+=/
    printf '+'
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

# Backspace on an empty query: go up one folder.
on_back() {
    local dir
    dir=$(cur_dir)
    [[ $dir == / ]] && return
    dir=$(dirname -- "$dir")
    [[ $dir == / ]] || dir+=/
    nav "$dir"
}

# Ctrl+F: switch between everything below and this folder only.
on_mode_toggle() {
    if [[ $(get_mode) == flat ]]; then
        echo tree >"$StateDir/mode"
    else
        echo flat >"$StateDir/mode"
    fi
    act change-border-label "$(label)"
    printf '+reload(load "$FZF_PROMPT")+first'
}

# Enter: hand the highlighted item (or the typed path) back to the main loop,
# which opens it once fzf has exited. URLs open right away.
on_enter() {
    local path=${1-} q=$FZF_QUERY target
    if (( FZF_MATCH_COUNT > 0 )) && [[ -n $path ]]; then
        target=$path
    elif [[ -z $q ]]; then
        return
    elif is_url "$q"; then
        spawn xdg-open "$q"
        printf 'abort'
        return
    else
        target=$(resolve "$q")
        if [[ ! -e $target ]]; then
            act change-border-label " Nothing matches: $q (alt-⏎ to run it) "
            return
        fi
    fi
    printf '%s' "$target" >"$StateDir/pick"
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

#region Opening files (runs in the kitty window after the main fzf exits)

# True if xdg-open would hand this file to xed: xed is the default for its
# type, or nothing is and it's text.
opens_in_xed() {
    local mime app
    command -v xdg-mime >/dev/null || return 1
    mime=$(xdg-mime query filetype "$1" 2>/dev/null) || return 1
    app=$(xdg-mime query default "$mime" 2>/dev/null)
    [[ $app == org.x.editor.desktop || ( -z $app && $mime == text/* ) ]]
}

# Ask xed or VSCodium in the same window. Returns 1 if cancelled with Esc.
choose_editor() {
    local choice
    choice=$(
        printf '1   xed\n2   VSCodium\n' |
            fzf \
                --prompt "Open $(basename -- "$1") with: " \
                --disabled --no-sort \
                --layout reverse --info hidden --cycle \
                --border --border-label " ⏎ open · 1/2 pick · esc back " \
                --border-label-pos 0:bottom \
                --bind '1:pos(1)+accept,2:pos(2)+accept' \
                --color "$FzfColors"
    )
    case ${choice:0:1} in
        1) spawn xed "$1" ;;
        2) spawn codium "$1" ;;
        *) return 1 ;;
    esac
}

# Open what Enter picked. Returns 1 if the editor choice was cancelled.
open_file() {
    if [[ -d $1 ]]; then
        spawn thunar "$1"
    elif command -v codium >/dev/null && opens_in_xed "$1"; then
        choose_editor "$1"
    else
        spawn xdg-open "$1"
    fi
}

#endregion

#region Main

run_ui() {
    echo $$ >"$PidFile"
    StateDir=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/runner.XXXXXX")
    export StateDir
    trap 'rm -rf "$StateDir"; rm -f "$PidFile"' EXIT
    trap 'exit 129' HUP
    trap 'exit 143' TERM

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
    FzfColors="
        fg:#ffffff, query:#ffffff,
        fg+:$lighter, prompt:$lighter, hl:$lighter, hl+:#ffffff,
        pointer:$lighter, selected-fg:$lighter, selected-bg:#000000,
        bg:#000000, bg+:$light, list-bg:#000000, gutter:#000000,
        border:$light, label:$light
    "

    export -f spawn run_in is_program run_file copy_text act cur_dir resolve \
        is_url get_mode label list_dir list_below load nav on_change \
        on_complete on_back on_mode_toggle on_enter on_run on_copy

    local dir="$HOME/" query="" path
    while :; do
        rm -f "$StateDir/pick"
        load "$dir" |
            fzf \
                --with-shell 'bash -c' \
                --delimiter '\t' --with-nth 2 \
                --scheme path \
                --prompt "$dir" --query "$query" \
                --layout reverse --info hidden --cycle \
                --border --border-label "$(label)" --border-label-pos 0:bottom \
                --bind 'change:transform:on_change' \
                --bind 'right:transform:on_complete {1}' \
                --bind 'tab:transform:on_complete {1}' \
                --bind 'backward-eof:transform:on_back' \
                --bind 'ctrl-f:transform:on_mode_toggle' \
                --bind 'enter:transform:on_enter {1}' \
                --bind 'alt-enter:transform:on_run {1}' \
                --bind 'ctrl-a:transform:nav /' \
                --bind 'ctrl-c:transform:on_copy {1}' \
                --color "$FzfColors"

        [[ -s $StateDir/pick ]] || break
        path=$(<"$StateDir/pick")
        open_file "$path" && break

        # Editor choice cancelled: back to the runner, on that file.
        dir=$(dirname -- "$path")
        [[ $dir == / ]] || dir+=/
        query=$(basename -- "$path")
    done
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
