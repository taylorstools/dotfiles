#!/usr/bin/env bash
#
# Colours from the wallpaper, for the shell and for your apps. Run by
# Services/Wallpaper.qml whenever the wallpaper or colour settings change.
#
#   generate.sh WALLPAPER SCHEME SEED_FLAGS...
#
#   1. the shell's palette  -> ~/.cache/qstest/colors.json (Theme reads it)
#   2. a terminal palette   -> ~/.cache/qstest/term16.json (term16.py)
#   3. app themes           -> GTK, niri, Ghostty, kitty, KDE, Zed, Firefox
#                              (templates.toml)
#   4. your own templates   -> ~/.config/matugen/config.toml
#   5. kitty and Ghostty are told to reload
#
# QSTEST_THEME_ROOT=/some/dir writes the app themes there instead of $HOME
# and skips steps 4 and 5, for trying it out.

set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
wall=$1
scheme=$2
shift 2
seed=("$@")

cache=${XDG_CACHE_HOME:-$HOME/.cache}/qstest
root=${QSTEST_THEME_ROOT:-$HOME}
mkdir -p "$cache"

matugen image "$wall" --type "$scheme" --mode dark --json hex --dry-run "${seed[@]}" >"$cache/colors.json.tmp" || exit 1
python3 "$here/term16.py" "$cache/colors.json.tmp" >"$cache/term16.json" || exit 1

sed -e "s|@ROOT@|$root|g" -e "s|@HERE@|$here|g" "$here/templates.toml" >"$cache/matugen-apps.toml"
matugen image "$wall" --type "$scheme" --mode dark "${seed[@]}" \
    -c "$cache/matugen-apps.toml" --import-json "$cache/term16.json" >/dev/null ||
    echo "app themes: matugen failed" >&2

if [[ -z ${QSTEST_THEME_ROOT:-} ]]; then
    user_config=${XDG_CONFIG_HOME:-$HOME/.config}/matugen/config.toml
    if [[ -f $user_config ]]; then
        matugen image "$wall" --type "$scheme" --mode dark "${seed[@]}" \
            -c "$user_config" --import-json "$cache/term16.json" >/dev/null ||
            echo "your matugen templates: matugen failed" >&2
    fi
    # kitty rereads its config (and the theme it includes) on SIGUSR1,
    # Ghostty on SIGUSR2. niri reloads colors.kdl by itself. NixOS can run
    # them under their .*-wrapped names.
    pkill -USR1 -x 'kitty|\.kitty-wrapped' 2>/dev/null
    pkill -USR2 -x 'ghostty|\.ghostty-wrapped' 2>/dev/null
fi

# Last, so the shell recolours once everything else is written.
mv "$cache/colors.json.tmp" "$cache/colors.json"
