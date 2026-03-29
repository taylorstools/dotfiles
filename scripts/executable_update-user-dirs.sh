#!/usr/bin/env bash

set -euo pipefail

CONFIG_FILE="$HOME/.config/user-dirs.dirs"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "User dirs config file not found."
  exit 1
fi

# Read each line
while IFS= read -r line; do
  # Skip comments and empty lines
  [[ -z "$line" || "$line" =~ ^# ]] && continue

  # Match lines like: XDG_XXX_DIR="..."
  if [[ "$line" =~ ^XDG_[A-Z_]+_DIR=\"(.*)\"$ ]]; then
    raw_path="${BASH_REMATCH[1]}"

    path="${raw_path/\$HOME/$HOME}"

    path="$(realpath -m "$path")"

    if [[ ! -d "$path" ]]; then
      echo "Creating $path."
      mkdir -p "$path"
    else
      echo "$path already exists."
    fi
  fi
done < "$CONFIG_FILE"

echo "Updating directories."
xdg-user-dirs-update