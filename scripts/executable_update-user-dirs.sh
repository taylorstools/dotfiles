#!/usr/bin/env bash

set -euo pipefail

CONFIG_FILE="$HOME/.config/user-dirs.dirs"

gum style \
  --border double --border-foreground 39 \
  --padding "1 4" --margin "1 0" \
  --bold "User Directories"

if [[ ! -f "$CONFIG_FILE" ]]; then
  gum log --level error "User dirs config file not found."
  exit 1
fi

# ===== Create missing directories =====

while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue

  if [[ "$line" =~ ^XDG_[A-Z_]+_DIR=\"(.*)\"$ ]]; then
    raw_path="${BASH_REMATCH[1]}"
    path="${raw_path/\$HOME/$HOME}"
    path="$(realpath -m "$path")"

    if [[ ! -d "$path" ]]; then
      gum log --level info "Creating $path"
      mkdir -p "$path"
    else
      gum log --level warn "$path already exists, skipping."
    fi
  fi
done < "$CONFIG_FILE"

# ===== Update xdg dirs =====

gum log --level info "Updating user directories..."
xdg-user-dirs-update

gum log --level info "Done."