#!/usr/bin/env bash
#
# Colours from the wallpaper, for the shell and for your apps. Run by
# Services/Wallpaper.qml whenever the wallpaper or colour settings change.
#
#   generate.sh WALLPAPER SCHEME SEED_FLAGS...
#
#   1. the shell's palette  -> ~/.cache/qstest/colors.json (Theme reads it)
#   2. a terminal palette   -> ~/.cache/qstest/term16.json (term16.py)
#   3. app themes           -> GTK, niri, Ghostty, kitty, KDE, Zed
#                              (templates.toml)
#   4. your own templates   -> ~/.config/matugen/config.toml
#   5. kitty and Ghostty are told to reload
#
# Nothing is redone when the wallpaper, scheme and seed are the ones last
# generated and none of this folder, the wallpaper or your matugen config
# has changed since (the shell runs this on every reload).
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
user_config=${XDG_CONFIG_HOME:-$HOME/.config}/matugen/config.toml
stamp=$cache/generated
failed=0
inputs=$(printf '%s\n' "$wall" "$scheme" "${seed[@]}")

if [[ -z ${QSTEST_THEME_ROOT:-} && -f $cache/colors.json && -f $stamp && $(<"$stamp") == "$inputs" ]] &&
    [[ -z $(find "$here" "$wall" "$user_config" -newer "$stamp" -print -quit 2>/dev/null) ]]; then
    exit 0
fi

matugen image "$wall" --type "$scheme" --mode dark --json hex --dry-run "${seed[@]}" >"$cache/colors.json.tmp" || exit 1
python3 "$here/term16.py" "$cache/colors.json.tmp" >"$cache/term16.json" || exit 1

sed -e "s|@ROOT@|$root|g" -e "s|@HERE@|$here|g" "$here/templates.toml" >"$cache/matugen-apps.toml"
matugen image "$wall" --type "$scheme" --mode dark "${seed[@]}" \
    -c "$cache/matugen-apps.toml" --import-json "$cache/term16.json" >/dev/null ||
    { echo "app themes: matugen failed" >&2; failed=1; }

# Sends a signal only to processes that listen for it. Helpers like
# `ghostty +ssh` share the app's name but don't handle USR1/USR2, so the signal
# would kill them, and the SSH session with them. Ghostty has a handler
# (SigCgt); kitty blocks the signal and reads it from a signalfd (SigBlk).
reload_app() {
    local signum=$1 names=$2 pid caught blocked
    for pid in $(pgrep -x "$names"); do
        caught=$(sed -n 's/^SigCgt:[[:space:]]*//p' "/proc/$pid/status" 2>/dev/null)
        blocked=$(sed -n 's/^SigBlk:[[:space:]]*//p' "/proc/$pid/status" 2>/dev/null)
        if [[ -n $caught && -n $blocked ]] && ((((0x$caught | 0x$blocked) >> (signum - 1)) & 1)); then
            kill "-$signum" "$pid" 2>/dev/null
        fi
    done
}

if [[ -z ${QSTEST_THEME_ROOT:-} ]]; then
    if [[ -f $user_config ]]; then
        matugen image "$wall" --type "$scheme" --mode dark "${seed[@]}" \
            -c "$user_config" --import-json "$cache/term16.json" >/dev/null ||
            { echo "your matugen templates: matugen failed" >&2; failed=1; }
    fi
    # kitty rereads its config (and the theme it includes) on SIGUSR1,
    # Ghostty on SIGUSR2. niri reloads colors.kdl by itself. NixOS can run
    # them under their .*-wrapped names, which the kernel cuts to 15 characters
    # (.ghostty-wrappe).
    reload_app 10 'kitty|\.kitty-wrapped'
    reload_app 12 'ghostty|\.ghostty-wrappe'
fi

# Last, so the shell recolours once everything else is written.
mv "$cache/colors.json.tmp" "$cache/colors.json"
# A failed step is retried next time.
if [[ -z ${QSTEST_THEME_ROOT:-} ]] && ((failed == 0)); then
    printf '%s\n' "$inputs" >"$stamp"
fi
