#!/usr/bin/env bash

set -euo pipefail

for cmd in niri jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "error: $cmd not found in PATH" >&2; exit 1; }
done

output="${1:-$(niri msg -j focused-output | jq -r '.name')}"

target=$(niri msg -j workspaces | jq -r --arg out "$output" '
  [ .[] | select(.output == $out and .name == null) ]
  | map(select(.active_window_id == null))
  | sort_by(.idx)
  | first
  | .idx // empty
')

if [[ -z "$target" ]]; then
  echo "error: no empty workspace found on output $output" >&2
  exit 1
fi

niri msg action focus-workspace "$target"