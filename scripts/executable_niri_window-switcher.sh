#!/usr/bin/env bash
#
# niri_window-switcher.sh: jump to any open niri window (fzf in a floating
# kitty window, like runner.sh).
#
# Each window is a line with the app's icon and "App: window title", in
# layout order: workspace by workspace, columns left to right (top to bottom
# within one), floating windows last. A gutter shows the workspace number on
# its first window, bright for the workspace you're on, with a dot on the
# window you came from. One letter on each line is underlined: press it and
# that window is focused right away. Focusing anything else (clicking away,
# a keybind) closes the switcher.
# Each window's letter comes from its app's name, preferring the start of a
# word and then the letters right after it, so the first Chrome window gets
# C, a second one gets H, and so on. Only when the app's name has no free
# letter left does it come from the window title, and failing that it's any
# free key, shown at the end of the line. A window keeps its letter until it
# closes (or niri restarts), however the list is ordered.
#
#   a-z, 0-9        focus the window with that letter underlined
#   Up/Down, Enter  move to a window and focus it (the cursor starts on the
#                   window you came from)
#   /               search: letters now type into the field to fuzzy-filter;
#                   Esc, or Backspace on an empty field, goes back to letters
#   Delete          close the highlighted window
#   Esc             close the switcher
#
# Run it with no arguments and it toggles: it opens the window, or closes it if
# it's already open.
#
# To open fast, it keeps one hidden kitty running in the background and opens
# its window from that, which skips kitty's startup (Python, the GPU, fonts).
# The first run starts it; "--warm" starts it without opening the switcher,
# for niri's spawn-at-startup, and also fills the icon caches in the
# background. It reads kitty.conf once, so after changing that run:
# kill "$(cat "$XDG_RUNTIME_DIR/niri_window-switcher.keepalive.pid")"
#
# Icons come from the apps' desktop entries and your GTK icon theme, drawn
# with kitty's graphics protocol. Everything is cached in
# ~/.cache/niri-window-switcher: an index of the icon theme (rebuilt when the
# theme's folders change), each app's icon, and SVGs converted to PNG.

set -uo pipefail

Self=$(realpath -- "${BASH_SOURCE[0]}")
PidFile="${XDG_RUNTIME_DIR:-/tmp}/niri_window-switcher.sh.pid"
KeepPidFile="${XDG_RUNTIME_DIR:-/tmp}/niri_window-switcher.keepalive.pid"
# Each window's letter, kept for the niri session (window IDs restart with
# niri, so the file is per niri socket).
LettersFile="${XDG_RUNTIME_DIR:-/tmp}/niri_window-switcher.letters.$(basename -- "${NIRI_SOCKET:-none}")"
ColorsFile="$HOME/.config/matugen/colors.conf"
CacheDir="${XDG_CACHE_HOME:-$HOME/.cache}/niri-window-switcher"
AppId="niri-window-switcher"
HintKeys="abcdefghijklmnopqrstuvwxyz0123456789"
HintPrompt="› "
SearchPrompt="/ "
HintGhost="press an underlined letter, or / to search"
SearchGhost="search windows"
export Self CacheDir LettersFile AppId HintKeys HintPrompt SearchPrompt HintGhost SearchGhost

#region Helpers

# Shorter names for apps whose desktop entry name is long, by app ID
# (lowercase). Anything not listed uses its desktop entry's Name=.
name_override() {
    case $1 in
        google-chrome) override="Chrome" ;;
        thunar) override="Thunar" ;;
    esac
}

# fzf action "name(arg)", picking a delimiter pair that doesn't occur in arg.
act() {
    local pair
    for pair in '()' '[]' '{}' '<>' '~~' '!!' '@@' '##' '%%' '^^' '&&' ';;' '||'; do
        if [[ $2 != *"${pair:1:1}"* ]]; then
            printf '%s%s%s%s' "$1" "${pair:0:1}" "$2" "${pair:1:1}"
            return
        fi
    done
}

# The hint keys as a comma list, for fzf's unbind()/rebind().
key_list() {
    local i out=""
    for ((i = 0; i < ${#HintKeys}; i++)); do
        out+="${HintKeys:i:1},"
    done
    printf '%s' "${out%,}"
}

in_search() { [[ ${FZF_PROMPT-} == "$SearchPrompt" ]]; }

label() {
    if [[ ${1-} == search ]]; then
        printf '%s' " type to filter · ⏎ focus · del close · esc back to letters "
    else
        printf '%s' " letter or ⏎ focus · / search · del close · esc quit "
    fi
}

focus_window() {
    niri msg action focus-window --id "$1" >/dev/null 2>&1
}

#endregion

#region Desktop entries and icons
#
# Everything here runs once per window while the list is built, so it avoids
# subshells: the helpers set variables of their caller (bash's dynamic scope)
# instead of printing, and the caches are read into memory once by load.

# The folders that hold desktop entries, in XDG precedence order.
desktop_dirs() {
    local IFS=: dir
    printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    for dir in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
        printf '%s\n' "$dir/applications"
    done
}

# Every desktop entry as "file ID, StartupWMClass, Name, Icon", separated by
# \x1f (a tab would collapse empty fields in read), in XDG precedence order
# (the first of a given ID wins).
desktop_index() {
    local dir
    while IFS= read -r dir; do
        [[ -d $dir ]] && find -L "$dir" -name '*.desktop' -type f -print0 2>/dev/null
    done < <(desktop_dirs) | xargs -0 -r awk '
        function emit(  id) {
            if (file == "") return
            id = file
            sub(/.*\//, "", id)
            sub(/\.desktop$/, "", id)
            print id "\037" wm "\037" name "\037" icon
        }
        FNR == 1 { emit(); file = FILENAME; sec = 0; name = icon = wm = "" }
        { sub(/\r$/, "") }
        /^\[/ { sec = ($0 == "[Desktop Entry]"); next }
        sec && name == "" && /^Name=/ { name = substr($0, 6) }
        sec && icon == "" && /^Icon=/ { icon = substr($0, 6) }
        sec && wm == "" && /^StartupWMClass=/ { wm = substr($0, 16) }
        END { emit() }
    '
}

# Brings the desktop entry index in $CacheDir/desktop.tsv up to date: it's
# rebuilt when one of the folders changes. The stamp is each folder's real
# path and mtime: on NixOS a rebuild swaps the store path behind
# /run/current-system (store mtimes are all 1), and editing your own entries
# changes ~/.local/share/applications' mtime.
update_desktop_index() {
    local index="$CacheDir/desktop.tsv" stamp_file="$CacheDir/desktop.stamp" stamp="" old="" dir
    local -a existing=()
    while IFS= read -r dir; do
        [[ -d $dir ]] && existing+=("$dir")
    done < <(desktop_dirs)
    if (( ${#existing[@]} )); then
        stamp=$(realpath -- "${existing[@]}"; stat -L -c '%y' -- "${existing[@]}")
    fi
    [[ -r $stamp_file ]] && old=$(<"$stamp_file")
    [[ -n $stamp && $stamp == "$old" && -r $index ]] && return
    mkdir -p "$CacheDir"
    desktop_index >"$index.tmp" && mv -f -- "$index.tmp" "$index"
    printf '%s' "$stamp" >"$stamp_file"
}

# Folders that hold icon themes, highest precedence first.
icon_bases() {
    local IFS=: dir
    printf '%s\n' "$HOME/.icons" "${XDG_DATA_HOME:-$HOME/.local/share}/icons"
    for dir in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
        printf '%s\n' "$dir/icons"
    done
}

# Your GTK icon theme, the themes it inherits from, then hicolor.
icon_themes() {
    local theme="" settings="$HOME/.config/gtk-3.0/settings.ini" base parent
    local -a queue=() seen=()
    if [[ -r $settings ]]; then
        theme=$(sed -n 's/^gtk-icon-theme-name[[:space:]]*=[[:space:]]*//p' "$settings" | head -n 1)
    fi
    if [[ -z $theme ]] && command -v gsettings >/dev/null; then
        theme=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
    fi
    [[ -n $theme ]] && queue+=("$theme")
    while (( ${#queue[@]} && ${#seen[@]} < 10 )); do
        theme=${queue[0]}
        queue=("${queue[@]:1}")
        [[ " ${seen[*]} " == *" $theme "* ]] && continue
        seen+=("$theme")
        while IFS= read -r base; do
            [[ -r $base/$theme/index.theme ]] || continue
            while IFS= read -r parent; do
                [[ -n $parent ]] && queue+=("$parent")
            done < <(sed -n 's/^Inherits[[:space:]]*=[[:space:]]*//p' "$base/$theme/index.theme" | tr ',' '\n')
            break
        done < <(icon_bases)
    done
    [[ " ${seen[*]} " == *" hicolor "* ]] || seen+=(hicolor)
    printf '%s\n' "${seen[@]}"
}

# Brings the icon index, $CacheDir/icon-index.tsv ("name<TAB>path" for every
# icon in your theme, the themes it inherits from, hicolor and pixmaps), up to
# date: one pass over the theme folders instead of a search per app. Rebuilt
# when the themes or their folders change; icons cached as not found are then
# looked up again.
update_icon_index() {
    # Once per process is enough.
    [[ -n ${IconIndexChecked-} ]] && return
    IconIndexChecked=1
    local index="$CacheDir/icon-index.tsv" stamp_file="$CacheDir/icon-index.stamp" stamp old=""
    local theme base dir rank=0
    local -a bases themes dirs=() pixmaps=()
    mapfile -t bases < <(icon_bases)
    mapfile -t themes < <(icon_themes)
    for theme in "${themes[@]}"; do
        for base in "${bases[@]}"; do
            [[ -d $base/$theme ]] && dirs+=("$rank"$'\t'"$base/$theme")
        done
        (( rank++ ))
    done
    for base in "${bases[@]}"; do
        dir="${base%/icons}/pixmaps"
        [[ -d $dir ]] && pixmaps+=("$dir")
    done
    stamp="${themes[*]}"$'\n'
    if (( ${#dirs[@]} + ${#pixmaps[@]} )); then
        stamp+=$(realpath -- "${dirs[@]#*$'\t'}" "${pixmaps[@]}"; stat -L -c '%y' -- "${dirs[@]#*$'\t'}" "${pixmaps[@]}")
    fi
    [[ -r $stamp_file ]] && old=$(<"$stamp_file")
    [[ $stamp == "$old" && -r $index ]] && return
    mkdir -p "$CacheDir"
    {
        for dir in "${dirs[@]}"; do
            find -L "${dir#*$'\t'}" -type f \( -name '*.svg' -o -name '*.svgz' -o -name '*.png' \) \
                -printf "${dir%%$'\t'*}\t%p\n" 2>/dev/null
        done
        for dir in "${pixmaps[@]}"; do
            find -L "$dir" -maxdepth 1 -type f \( -name '*.png' -o -name '*.svg' -o -name '*.xpm' \) \
                -printf "$rank\t%p\n" 2>/dev/null
        done
    } | awk -F'\t' '
        # Per name: the earliest theme wins; within it, scalable, else the
        # largest size.
        {
            path = $2
            name = path
            sub(/.*\//, "", name)
            sub(/\.(png|svgz?|xpm)$/, "", name)
            size = 0
            if (path ~ /\/scalable\//) size = 100000
            else if (match(path, /\/[0-9]+x[0-9]+(@[0-9]+x?)?\//)) size = substr(path, RSTART + 1) + 0
            else if (match(path, /\/[0-9]+\//)) size = substr(path, RSTART + 1) + 0
            if (!(name in best) || ($1 + 0 == rank[name] && size > bsize[name])) {
                best[name] = path
                rank[name] = $1 + 0
                bsize[name] = size
            }
        }
        END { for (n in best) print n "\t" best[n] }
    ' >"$index.tmp" && mv -f -- "$index.tmp" "$index"
    printf '%s' "$stamp" >"$stamp_file"
    # Forget the icons that weren't found, so they're looked up in the new
    # index.
    if [[ -r $CacheDir/icons.tsv ]]; then
        awk -F'\t' '$2 != "-"' "$CacheDir/icons.tsv" >"$CacheDir/icons.tsv.tmp" &&
            mv -f -- "$CacheDir/icons.tsv.tmp" "$CacheDir/icons.tsv"
    fi
}

# Path of the best file for icon name $1, from the icon index.
find_icon() {
    update_icon_index
    awk -F'\t' -v n="$1" '$1 == n { print $2; exit }' "$CacheDir/icon-index.tsv" 2>/dev/null
}

# A PNG of image $1 for kitty (which only takes PNG), converting into the
# cache when needed.
to_png() {
    local src=$1 out
    if [[ $src == *.png ]]; then
        printf '%s' "$src"
        return
    fi
    mkdir -p "$CacheDir/icons"
    out="$CacheDir/icons/$(printf '%s' "$src" | md5sum | cut -c1-16).png"
    if [[ ! -s $out ]]; then
        if [[ $src == *.svg || $src == *.svgz ]] && command -v rsvg-convert >/dev/null; then
            rsvg-convert -w 128 -h 128 -a -o "$out" "$src" 2>/dev/null
        elif command -v magick >/dev/null; then
            magick -background none -density 384 "$src" -resize 128x128 "png:$out" 2>/dev/null
        elif command -v convert >/dev/null; then
            convert -background none -density 384 "$src" -resize 128x128 "png:$out" 2>/dev/null
        fi
    fi
    [[ -s $out ]] && printf '%s' "$out"
}

# Sets png to the PNG for a desktop entry's Icon= value $1 ("" if none).
# Uses load's in-memory icon_cache, adding what it looks up to the cache
# file: the PNG, "-" for no icon, or "!" plus the source when it couldn't be
# converted without rsvg-convert (retried once rsvg-convert is installed).
icon_png() {
    local value=$1 src="" hit
    png=""
    [[ -n $value ]] || return
    hit=${icon_cache[$value]-}
    if [[ $hit == - ]]; then
        return
    elif [[ $hit == '!'* ]]; then
        command -v rsvg-convert >/dev/null || return
        src=${hit:1}
    elif [[ -n $hit && -s $hit ]]; then
        png=$hit
        return
    elif [[ $value == /* ]]; then
        [[ -f $value ]] && src=$value
    else
        src=$(find_icon "$value")
    fi
    [[ -n $src ]] && png=$(to_png "$src")
    if [[ -n $png ]]; then
        hit=$png
    elif [[ -z $src ]]; then
        hit=-
    elif command -v rsvg-convert >/dev/null; then
        hit=-
    else
        hit="!$src"
    fi
    icon_cache[$value]=$hit
    mkdir -p "$CacheDir"
    printf '%s\t%s\n' "$value" "$hit" >>"$CacheDir/icons.tsv"
}

# Sets cells to the two cells that show PNG $1: kitty Unicode placeholders,
# with the image ID in the 256-color foreground. A new image is sent to kitty
# first, quietly, as a virtual placement 2 cells wide and 1 tall. Image IDs
# live in load's icon_ids, saved in the state folder for reloads.
icon_cells() {
    local png=$1 id
    local p=$'\xf4\x8e\xbb\xae' d0=$'\xcc\x85' d1=$'\xcc\x8d'
    cells="  "
    [[ -n $png ]] || return
    id=${icon_ids[$png]-}
    if [[ -z $id ]]; then
        (( ${#icon_ids[@]} < 255 )) || return
        id=$(( ${#icon_ids[@]} + 1 ))
        icon_ids[$png]=$id
        printf '%s\t%s\n' "$id" "$png" >>"$StateDir/icon-ids"
        printf '\e_Ga=T,U=1,q=2,C=1,f=100,t=f,i=%s,c=2,r=1;%s\e\\' \
            "$id" "$(printf '%s' "$png" | base64 -w 0)" >/dev/tty
    fi
    printf -v cells '\e[38;5;%sm%s%s%s%s%s%s\e[0m' "$id" "$p" "$d0" "$d0" "$p" "$d0" "$d1"
}

#endregion

#region Hint letters

# Appends to cand the hint candidates in string $2 as "key:src:pos" words,
# src being $1: word starts first (after a non-alphanumeric, or a capital
# after a lowercase letter), then every other letter, each in order.
hint_candidates() {
    local src=$1 s=$2 i c prev="" key starts="" rest=""
    for ((i = 0; i < ${#s}; i++)); do
        c=${s:i:1}
        key=${c,}
        if [[ ${#key} == 1 && $HintKeys == *"$key"* ]]; then
            if [[ -z $prev || $prev != [[:alnum:]] || ($c == [[:upper:]] && $prev == [[:lower:]]) ]]; then
                starts+="$key:$src:$i "
            else
                rest+="$key:$src:$i "
            fi
        fi
        prev=$c
    done
    cand+="$starts$rest"
}

# Appends to line $1 with the character at $2 styled as the hint, the rest in
# style $3.
styled() {
    local s=$1 pos=$2 base=$3 reset=$'\e[0m'
    if (( pos < 0 )); then
        line+="$base$s$reset"
    else
        line+="$base${s:0:pos}$HintStyle${s:pos:1}$reset$base${s:pos+1}$reset"
    fi
}

#endregion

#region List producer (fed to fzf as "window ID<TAB>key<TAB>display")

# Builds the list in both forms, $StateDir/list (each workspace's number on
# its first window only) and $StateDir/list-search (on every window, for
# searching, when the rows are filtered apart), and prints the one for $1
# ("search" or nothing).
load() {
    local id app title lapp entry name icon png desk_name suffix i r tok key rest progress
    local cand cells line npos tpos tag fallback="" override wsid wsidx wscur prev_ws=""
    local num bar gutter gutter_all
    local -A by_id=() by_wm=() used=() icon_cache=() icon_ids=()
    local -a ids=() names=() titles=() pngs=() cands=() hint=() hsrc=() hpos=() toks=()
    local -a wsids=() wsidxs=() wscurs=()

    for ((i = 0; i < ${#HintKeys}; i++)); do
        fallback+="${HintKeys:i:1}:x:-1 "
    done

    update_desktop_index

    while IFS=$'\x1f' read -r id app name icon; do
        [[ -n $id ]] || continue
        [[ -n ${by_id[${id,,}]+x} ]] || by_id[${id,,}]="$name"$'\t'"$icon"
        [[ -z $app || -n ${by_wm[${app,,}]+x} ]] || by_wm[${app,,}]="$name"$'\t'"$icon"
    done <"$CacheDir/desktop.tsv"

    if [[ -r $CacheDir/icons.tsv ]]; then
        while IFS=$'\t' read -r key png; do
            [[ -n $key ]] && icon_cache[$key]=$png
        done <"$CacheDir/icons.tsv"
    fi
    if [[ -r $StateDir/icon-ids ]]; then
        while IFS=$'\t' read -r id png; do
            [[ -n $png ]] && icon_ids[$png]=$id
        done <"$StateDir/icon-ids"
    fi

    while IFS=$'\x1f' read -r id wsid wsidx wscur app title; do
        lapp=${app,,}
        entry=""
        if [[ -n ${lapp##*.} ]]; then
            entry=${by_id[$lapp]-${by_wm[$lapp]-${by_id[${lapp##*.}]-}}}
        fi
        desk_name=${entry%%$'\t'*}
        icon=${entry#*$'\t'}
        [[ -n $entry ]] || icon=""
        override=""
        name_override "$lapp"
        name=${override:-$desk_name}
        if [[ -z $name ]]; then
            name=${app##*.}
            name=${name//[-_]/ }
            name=${name^}
        fi
        [[ -n $name ]] || name="Window"

        # "Page - Google Chrome" -> "Page".
        for suffix in " - $desk_name" " — $desk_name" " – $desk_name" " - $name" " — $name" " – $name"; do
            [[ ${#suffix} -gt 3 && ${title,,} == *"${suffix,,}" ]] || continue
            title=${title:0:${#title}-${#suffix}}
            break
        done
        [[ ${title,,} == "${name,,}" ]] && title=""

        ids+=("$id")
        wsids+=("$wsid")
        wsidxs+=("$wsidx")
        wscurs+=("$wscur")
        names+=("$name")
        titles+=("$title")
        # The entry's icon, else one named after the app ID, else a generic one.
        icon_png "$icon"
        [[ -n $png || -z $app ]] || icon_png "$app"
        [[ -n $png ]] || icon_png application-x-executable
        pngs+=("$png")
        cand=""
        hint_candidates n "$name"
        hint_candidates t "$title"
        cands+=("$cand$fallback")
    done < <(
        # In layout order: monitors left to right, then workspaces in order,
        # then columns left to right and top to bottom in a column, floating
        # windows last.
        niri msg --json windows 2>/dev/null | jq -r --arg skip "$AppId" \
            --argjson ws "$(niri msg --json workspaces 2>/dev/null || echo '[]')" \
            --argjson outs "$(niri msg --json outputs 2>/dev/null || echo '{}')" '
            ($outs | to_entries
                | map([(.value.logical.x // 1e9), (.value.logical.y // 1e9), .key])
                | sort | to_entries | map({(.value[2]): .key}) | add // {}) as $orank
            | ($ws | map({(.id | tostring): .}) | add // {}) as $wsm
            | map(select(.app_id != $skip)
                | ($wsm[(.workspace_id // -1) | tostring] // {}) as $w
                | . + {
                    _key: [
                        ($orank[$w.output // ""] // 99),
                        ($w.idx // 999),
                        (if .is_floating then 1 else 0 end),
                        (.layout.pos_in_scrolling_layout[0]? // 0),
                        (.layout.pos_in_scrolling_layout[1]? // 0),
                        .id
                    ],
                    _ws: $w
                })
            | sort_by(._key)
            | .[]
            | [
                .id, (._ws.id // ""), (._ws.idx // ""), (if ._ws.is_focused then 1 else 0 end),
                (.app_id // "" | gsub("[[:cntrl:]]"; "")), (.title // "" | gsub("[[:cntrl:]]"; " "))
              ]
            | map(tostring) | join("\u001f")
        '
    )

    # A window keeps the letter it was first given for the rest of the niri
    # session. The underline goes on that letter where it still occurs (the
    # title may have changed), else it's shown at the end of the line.
    local -A open=() kept=()
    for i in "${!ids[@]}"; do
        open[${ids[i]}]=1
    done
    if [[ -r $LettersFile ]]; then
        while IFS=$'\t' read -r id key; do
            [[ -n ${open[$id]+x} && -n $key && -z ${used[$key]+x} ]] || continue
            kept[$id]=$key
            used[$key]=1
        done <"$LettersFile"
    fi
    for i in "${!ids[@]}"; do
        key=${kept[${ids[i]}]-}
        [[ -n $key ]] || continue
        hint[i]=$key
        read -ra toks <<<"${cands[i]}"
        for tok in "${toks[@]}"; do
            [[ ${tok%%:*} == "$key" ]] || continue
            rest=${tok#*:}
            hsrc[i]=${rest%%:*}
            hpos[i]=${rest#*:}
            break
        done
    done

    # New windows get letters in rounds: every one tries its best candidate,
    # then its second best, and so on, so no window's first pick is taken by
    # another window's tenth.
    r=0
    progress=1
    while (( progress )); do
        progress=0
        for i in "${!ids[@]}"; do
            [[ -n ${hint[i]-} ]] && continue
            read -ra toks <<<"${cands[i]}"
            (( r < ${#toks[@]} )) || continue
            progress=1
            tok=${toks[r]}
            key=${tok%%:*}
            [[ -n ${used[$key]+x} ]] && continue
            used[$key]=1
            rest=${tok#*:}
            hint[i]=$key
            hsrc[i]=${rest%%:*}
            hpos[i]=${rest#*:}
        done
        (( r++ ))
    done

    # (Not when the list came back empty, which can just be niri not answering.)
    if (( ${#ids[@]} )); then
        for i in "${!ids[@]}"; do
            [[ -n ${hint[i]-} ]] && printf '%s\t%s\n' "${ids[i]}" "${hint[i]}"
        done >"$LettersFile.$$" && mv -f -- "$LettersFile.$$" "$LettersFile"
    fi

    : >"$StateDir/hints"
    : >"$StateDir/list"
    : >"$StateDir/list-search"
    for i in "${!ids[@]}"; do
        npos=-1
        tpos=-1
        tag=""

        # The gutter: the workspace number, bright for the workspace you're
        # on and dim for the others, then a dot on the window you came from.
        printf -v num '%2s' "${wsidxs[i]}"
        bar=" "
        [[ ${ids[i]} == "${FromId-}" ]] && bar="●"
        if [[ ${wscurs[i]} == 1 ]]; then
            gutter_all=$'\e[1m'"$num"$'\e[0m '"$AccentStyle$bar"$'\e[0m '
            gutter="   $AccentStyle$bar"$'\e[0m '
        else
            gutter_all=$'\e[2m'"$num $bar"$'\e[0m '
            gutter=$'\e[2m'"   $bar"$'\e[0m '
        fi
        [[ ${wsids[i]} != "$prev_ws" ]] && gutter=$gutter_all
        prev_ws=${wsids[i]}

        case ${hsrc[i]-} in
            n) npos=${hpos[i]} ;;
            t) tpos=${hpos[i]} ;;
            x) tag="  $HintStyle${hint[i]}"$'\e[0m' ;;
        esac
        icon_cells "${pngs[i]}"
        line="$cells "
        styled "${names[i]}" "$npos" $'\e[1m'
        if [[ -n ${titles[i]} ]]; then
            line+=": "
            styled "${titles[i]}" "$tpos" ""
        fi
        line+=$tag
        printf '%s\t%s\t%s\n' "${ids[i]}" "${hint[i]-}" "$gutter$line" >>"$StateDir/list"
        printf '%s\t%s\t%s\n' "${ids[i]}" "${hint[i]-}" "$gutter_all$line" >>"$StateDir/list-search"
        [[ -n ${hint[i]-} ]] && printf '%s\t%s\n' "${hint[i]}" "${ids[i]}" >>"$StateDir/hints"
    done
    if [[ ${1-} == search ]]; then
        cat -- "$StateDir/list-search"
    else
        cat -- "$StateDir/list"
    fi
}

#endregion

#region fzf event handlers (each prints the fzf actions to run)

# A letter in letter mode: focus its window.
on_hint() {
    local id
    id=$(awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "$StateDir/hints")
    if [[ -n $id ]]; then
        focus_window "$id"
        printf 'abort'
    else
        act change-border-label " No window on ${1^^} "
    fi
}

on_enter() {
    [[ -n ${1-} ]] || return
    focus_window "$1"
    printf 'abort'
}

# "/": start searching (letters type again), or type a "/" when already
# searching.
on_slash() {
    if in_search; then
        printf 'put(/)'
        return
    fi
    printf 'unbind(%s)+' "$(key_list)"
    act change-prompt "$SearchPrompt"
    printf '+'
    act change-ghost "$SearchGhost"
    printf '+'
    act change-border-label "$(label search)"
    # Rows get filtered apart, so show the workspace number on every one.
    printf '+reload(cat -- "$StateDir/list-search")'
}

# Back to letter mode.
leave_search() {
    printf 'rebind(%s)+clear-query+' "$(key_list)"
    act change-prompt "$HintPrompt"
    printf '+'
    act change-ghost "$HintGhost"
    printf '+'
    act change-border-label "$(label)"
    printf '+reload(cat -- "$StateDir/list")'
}

on_esc() {
    if in_search; then
        leave_search
    else
        printf 'abort'
    fi
}

on_back() {
    in_search && leave_search
}

# Delete: close the highlighted window and refresh the list once it's gone.
on_close() {
    [[ -n ${1-} ]] || return
    niri msg action close-window --id "$1" >/dev/null 2>&1
    if in_search; then
        printf 'reload(sleep 0.3; load search)'
    else
        printf 'reload(sleep 0.3; load)'
    fi
}

#endregion

#region Closing on focus loss

# Watch niri's events and close switcher $1 (its process group) once focus
# moves to anything else, after its own window has had focus. The first
# events describe the current state, so this also works if the window was
# focused before the watch started.
watch_focus() {
    local kind id seen=0
    local -A mine=()
    niri msg --json event-stream 2>/dev/null |
        jq --unbuffered -r --arg app "$AppId" '
            if .WindowsChanged then
                .WindowsChanged.windows[] | select(.app_id == $app) | "mine \(.id)"
            elif .WindowOpenedOrChanged then
                .WindowOpenedOrChanged.window | select(.app_id == $app) | "mine \(.id)"
            elif .WindowFocusChanged then
                "focus \(.WindowFocusChanged.id // "none")"
            else
                empty
            end
        ' |
        while read -r kind id; do
            if [[ $kind == mine ]]; then
                mine[$id]=1
            elif [[ -n ${mine[$id]+x} ]]; then
                seen=1
            elif (( seen )); then
                kill -- "-$1" 2>/dev/null
                break
            fi
        done
}

#endregion

#region Background kitty

# Fill the caches ahead of time (run by --warm at a low priority): the
# desktop entry and icon indexes, and the icon of every installed app, so a
# window from an app the switcher hasn't shown before costs nothing extra.
warm_caches() {
    local id app name icon key png
    local -A icon_cache=()
    update_desktop_index
    update_icon_index
    if [[ -r $CacheDir/icons.tsv ]]; then
        while IFS=$'\t' read -r key png; do
            [[ -n $key ]] && icon_cache[$key]=$png
        done <"$CacheDir/icons.tsv"
    fi
    while IFS=$'\x1f' read -r id app name icon; do
        [[ -n $icon ]] && icon_png "$icon"
    done <"$CacheDir/desktop.tsv"
    icon_png application-x-executable
}

# True if the hidden kitty instance is running (its placeholder process is).
keepalive_running() {
    local pid
    [[ -r $KeepPidFile ]] && read -r pid <"$KeepPidFile" && [[ $pid =~ ^[0-9]+$ ]] &&
        grep -qF "$Self" "/proc/$pid/cmdline" 2>/dev/null
}

# Start the hidden kitty instance, detached, unless it's already running.
start_keepalive() {
    keepalive_running && return
    (trap '' HUP; setsid -f kitty --single-instance --instance-group "$AppId" --start-as=hidden \
        --class "$AppId" --title "Windows (background)" "$Self" --keepalive \
        </dev/null >/dev/null 2>&1)
}

# What runs in the hidden window: nothing, until kitty or the session ends.
run_keepalive() {
    echo $$ >"$KeepPidFile"
    sleep infinity &
    trap 'kill "$!" 2>/dev/null; rm -f "$KeepPidFile"' EXIT
    trap 'exit 129' HUP
    trap 'exit 143' TERM
    wait
}

#endregion

#region Main

run_ui() {
    echo $$ >"$PidFile"
    StateDir=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/niri_window-switcher.XXXXXX")
    FromId=${1-}
    export StateDir FromId
    WatchPid=""
    trap 'rm -rf "$StateDir"; rm -f "$PidFile"; [[ -n $WatchPid ]] && kill -- "-$WatchPid" 2>/dev/null' EXIT
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
    local fzf_colors="
        fg:#ffffff, query:#ffffff, ghost:$light,
        fg+:$lighter, prompt:$lighter, hl:$lighter, hl+:#ffffff,
        pointer:$lighter, selected-fg:$lighter, selected-bg:#000000,
        bg:#000000, bg+:$light, list-bg:#000000, gutter:-1,
        border:$light, label:$light
    "
    # The hint letter: bold, underlined, in the theme's accent.
    printf -v AccentStyle '\e[38;2;%d;%d;%dm' "0x${lighter:1:2}" "0x${lighter:3:2}" "0x${lighter:5:2}"
    HintStyle=$'\e[1;4m'$AccentStyle
    export AccentStyle HintStyle

    export -f name_override act key_list in_search label focus_window \
        desktop_dirs desktop_index update_desktop_index update_icon_index icon_bases icon_themes find_icon to_png icon_png icon_cells \
        hint_candidates styled load on_hint on_enter on_slash leave_search on_esc \
        on_back on_close watch_focus

    # kitty keeps separate images for the main and alternate screens, and fzf
    # draws on the alternate one, so switch to it first, then build the list
    # (which sends the icons). fzf switching again is then a no-op.
    printf '\e[?1049h' >/dev/tty
    load >/dev/null
    if [[ ! -s $StateDir/list ]]; then
        echo "No windows open (or niri IPC unavailable)."
        sleep 1.5
        return
    fi

    # Start on the window you came from.
    local start
    start=$(awk -F'\t' -v id="$FromId" '$1 == id { print NR; exit }' "$StateDir/list")

    local -a binds=() i
    for ((i = 0; i < ${#HintKeys}; i++)); do
        binds+=(--bind "${HintKeys:i:1}:transform:on_hint ${HintKeys:i:1}")
    done

    # In its own process group (so it can be stopped as a whole, niri msg and
    # jq included), away from the terminal.
    setsid bash -c 'watch_focus "$1"' _ "$$" </dev/null >/dev/null 2>&1 &
    WatchPid=$!

    # --height 100% uses fzf's light renderer, which doesn't clear the screen
    # (and the icons with it) the way the full-screen one can.
    fzf <"$StateDir/list" \
        --with-shell 'bash -c' \
        --ansi --delimiter '\t' --with-nth 3 \
        --no-sort --tiebreak index \
        --height 100% --layout reverse --info hidden --cycle --gutter ' ' \
        --prompt "$HintPrompt" --ghost "$HintGhost" \
        --border --border-label "$(label)" --border-label-pos 0:bottom \
        "${binds[@]}" \
        --bind "load:pos(${start:-1})+unbind(load)" \
        --bind '/:transform:on_slash' \
        --bind 'esc:transform:on_esc' \
        --bind 'backward-eof:transform:on_back' \
        --bind 'enter:transform:on_enter {1}' \
        --bind 'del:transform:on_close {1}' \
        --color "$fzf_colors"
}

# Toggle: close the open switcher (if its PID is still one), else launch.
toggle() {
    local pid from=""
    if [[ -r $PidFile ]] && read -r pid <"$PidFile" && [[ $pid =~ ^[0-9]+$ ]] &&
        grep -qF "$Self" "/proc/$pid/cmdline" 2>/dev/null; then
        kill -- "-$pid" 2>/dev/null || kill "$pid"
        exit 0
    fi
    # Note the window you're on now, before the switcher takes focus.
    if [[ $(niri msg --json focused-window 2>/dev/null) =~ ^\{\"id\":([0-9]+) ]]; then
        from=${BASH_REMATCH[1]}
    fi
    if keepalive_running; then
        exec kitty --single-instance --instance-group "$AppId" \
            --title "Windows" --class "$AppId" "$Self" --ui "$from"
    fi
    # Not running yet: start it for next time, and open this one the slow way
    # rather than racing it.
    start_keepalive
    exec kitty --title "Windows" --class "$AppId" "$Self" --ui "$from"
}

case ${1-} in
    --ui) run_ui "${2-}" ;;
    --keepalive) run_keepalive ;;
    --warm)
        start_keepalive
        (trap '' HUP; setsid -f nice -n 19 "$Self" --warm-caches </dev/null >/dev/null 2>&1)
        ;;
    --warm-caches) warm_caches ;;
    *) toggle ;;
esac

#endregion
