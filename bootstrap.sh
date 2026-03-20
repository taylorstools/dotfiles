#!/usr/bin/env bash

set -e

REPO="https://github.com/taylorstools/dotfiles"
DOTFILES_DIR="$HOME/.dotfiles"
GREEN="\e[32m"
RESET="\e[0m"

echo -e "${GREEN}Installing required packages...${RESET}"
nix-shell -p git nix --run "true"

echo
echo -e "${GREEN}Cloning dotfiles...${RESET}"
if [ ! -d "$DOTFILES_DIR" ]; then
  git clone "$REPO" "$DOTFILES_DIR"
else
  echo "Dotfiles already exist, pulling latest..."
  git -C "$DOTFILES_DIR" pull
fi

# List all applicable hosts
echo
hosts=()
for dir in "$DOTFILES_DIR/nixos/hosts"/*/; do
  [ -d "$dir" ] || continue
  hosts+=("$(basename "$dir")")
done

echo -e "${GREEN}Choose the host for this configuration:${RESET}"
PS3="==> "
select HOST in "${hosts[@]}"; do
  if [ -n "$HOST" ]; then
    echo
    echo "Selected host: $HOST"
    break
  fi
done

echo
echo -e "${GREEN}Updating Nix flake...${RESET}"
nix --extra-experimental-features "nix-command flakes" \
  flake update --flake "$DOTFILES_DIR/nixos"

echo
echo -e "${GREEN}Applying system configuration...${RESET}"
sudo nixos-rebuild switch --flake "$DOTFILES_DIR/nixos#$HOST"

echo
echo -e "${GREEN}Installing chezmoi...${RESET}"
nix profile install nixpkgs#chezmoi

echo
echo -e "${GREEN}Applying dotfiles...${RESET}"
chezmoi init --apply "$DOTFILES_DIR"

echo
echo -e "${GREEN}Done!${RESET}"
read -rp "Do you want to reboot now? [Y/n] " REBOOT_ANSWER
REBOOT_ANSWER=${REBOOT_ANSWER:-y}

case "$REBOOT_ANSWER" in
  [yY]|[yY][eE][sS])
    sudo reboot;;
esac