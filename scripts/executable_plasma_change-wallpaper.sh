#!/usr/bin/env bash

set -euo pipefail

WALLPAPER_DIR="$HOME/.dotfiles/Wallpapers"
CURRENT_WALLPAPER=$(grep -r "Image=" ~/.config/plasma-org.kde.plasma.desktop-appletsrc \
  | head -1 \
  | cut -d'=' -f2 \
  | sed 's|file://||')

FIND_ARGS=(
  "$WALLPAPER_DIR"
  -maxdepth 1
  -type f
)

# Exclude current wallpaper if it exists
if [[ -e "$CURRENT_WALLPAPER" ]]; then
  FIND_ARGS+=( ! -samefile "$CURRENT_WALLPAPER" )
fi

WALLPAPER="$(find "${FIND_ARGS[@]}" | shuf -n 1)"

[[ -n "$WALLPAPER" ]] || exit 0

plasma-apply-wallpaperimage "$WALLPAPER"