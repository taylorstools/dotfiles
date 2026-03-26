#!/usr/bin/env bash

set -e

REPO="https://github.com/taylorstools/dotfiles"
DOTFILES_DIR="$HOME/.dotfiles"
GREEN=$'\e[32m'
RESET=$'\e[0m'

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

if [[ -z "$HOST" ]]; then
  echo
  echo "No host selected, aborting."
  exit 1
fi

if [[ "$HOST" == "taylorpc" ]]; then
  echo
  read -rp "${GREEN}Do you want to configure rEFInd? [Y/n]${RESET} " REFIND_ANSWER
  REFIND_ANSWER=${REFIND_ANSWER:-y}
fi

sudo cp -f "/etc/nixos/hardware-configuration.nix" "$HOME/.dotfiles/nixos/hosts/$HOST/hardware-configuration.nix"

echo
echo -e "${GREEN}Updating Nix flake...${RESET}"
nix --extra-experimental-features "nix-command flakes" \
  flake update --flake "$DOTFILES_DIR/nixos"

echo
echo -e "${GREEN}Applying system configuration...${RESET}"
sudo nixos-rebuild switch --flake "$DOTFILES_DIR/nixos#$HOST"

echo
echo -e "${GREEN}Installing chezmoi...${RESET}"
nix profile add nixpkgs#chezmoi

echo
echo -e "${GREEN}Applying dotfiles...${RESET}"
chezmoi init --apply "$DOTFILES_DIR" --force

case "$REFIND_ANSWER" in
  [yY]|[yY][eE][sS])
    echo
    echo -e "${GREEN}Configuring rEFInd...${RESET}"
    "$HOME/scripts/rEFInd/nix_install-refind.sh"
    ;;
  *)
    echo
    ;;
esac

echo -e "${GREEN}Done!${RESET}"
read -rp "Do you want to reboot now? [Y/n] " REBOOT_ANSWER
REBOOT_ANSWER=${REBOOT_ANSWER:-y}

case "$REBOOT_ANSWER" in
  [yY]|[yY][eE][sS])
    [ -d /etc/nixos ] && sudo rm -rf /etc/nixos
    sudo reboot;;
esac