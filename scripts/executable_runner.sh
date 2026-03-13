#!/usr/bin/env bash

# Toggle (quit runner if it's already open)
PIDFILE="$XDG_RUNTIME_DIR/runner.sh.pid"

if [ -f "$PIDFILE" ]; then
    oldpid="$(cat "$PIDFILE")"
    if kill -0 "$oldpid" 2>/dev/null; then
        kill "$oldpid"
        exit 0
    fi
fi

echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

COLORS="$HOME/.config/matugen/colors.conf"

# Extract colors
LIGHT=$(grep '^\$light[[:space:]]*=' "$COLORS" | cut -d'(' -f2 | cut -c1-6 | sed 's/^/#/')
LIGHTER=$(grep '^\$lighter[[:space:]]*=' "$COLORS" | cut -d'(' -f2 | cut -c1-6 | sed 's/^/#/')

# Pipe fd to fzf
SELECTED=$(
  fd . --hidden -tf -td --case-sensitive / |
    fzf \
      --layout reverse \
      --info hidden \
      --border \
      --query "/home/taylor/" \
      --bind "ctrl-a:execute-silent(echo {q} | xclip -selection clipboard)+change-query(/)" \
      --color " \
        fg:#ffffff, \
        fg+:$LIGHTER, \
        prompt:$LIGHTER, \
        hl:$LIGHTER, \
        hl+:#ffffff, \
        pointer:$LIGHTER, \
        selected-fg:$LIGHTER, \
        selected-bg:#000000, \
        bg:#000000, \
        bg+:$LIGHT, \
        list-bg:#000000, \
        border:$LIGHT \
      "
)

# If a selection was made...
if [[ -n "$SELECTED" ]]; then
    if [[ -d "$SELECTED" ]]; then
        # Open directories with Thunar
        setsid thunar "$SELECTED" >/dev/null 2>&1 &
    else
        # Open everything else with xdg default
        setsid xdg-open "$SELECTED" >/dev/null 2>&1 &
    fi
    sleep 0.25
fi