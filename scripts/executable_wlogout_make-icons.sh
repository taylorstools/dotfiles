#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

COLORS="$HOME/.config/matugen/colors.conf"
DEFAULT_ICONS="$HOME/.config/wlogout/icons/default"

# Extract colors
LIGHT=$(grep '^\$light[[:space:]]*=' "$COLORS" | cut -d'(' -f2 | cut -c1-6 | sed 's/^/#/')
LIGHTER=$(grep '^\$lighter[[:space:]]*=' "$COLORS" | cut -d'(' -f2 | cut -c1-6 | sed 's/^/#/')

colorize_icons() {
    local outdir="$1"
    local color="$2"

    mkdir -p "$outdir"

    for file in "$DEFAULT_ICONS"/*.png; do
        filename="${file##*/}"
        magick "$file" -fill "$color" -opaque "#FFFFFF" "$outdir/$filename"
    done
}

colorize_icons "$HOME/.config/wlogout/icons/active" "$LIGHT"
colorize_icons "$HOME/.config/wlogout/icons/hover"  "$LIGHTER"