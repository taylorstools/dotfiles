#!/usr/bin/env bash

set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Error: Script should not be ran with sudo or as root."
  exit 1
fi

REPO="https://github.com/taylorstools/dotfiles"
DOTFILES_DIR="$HOME/.dotfiles"
GREEN=$'\e[32m'
RESET=$'\e[0m'

echo -e "${GREEN}Cloning dotfiles...${RESET}"
if [ ! -d "$DOTFILES_DIR" ]; then
  git clone "$REPO" "$DOTFILES_DIR"
else
  echo "Dotfiles already exist, pulling latest..."
  git -C "$DOTFILES_DIR" pull
fi

# List all applicable hosts
hosts=()
for dir in "$DOTFILES_DIR/nixos/hosts"/*/; do
  [ -d "$dir" ] || continue
  hosts+=("$(basename "$dir")")
done

# Prompt user to select host
echo
HOST=$(printf "%s\n" "${hosts[@]}" | gum choose --header "Choose the host for this configuration:")

[ -z "$HOST" ] && { echo; echo "No host selected."; exit 1; }

# Ask user if they want to configure rEFInd
REFIND_ANSWER="n"
if [[ "$HOST" == "taylorpc" ]]; then
  read -rp "${GREEN}Do you want to configure rEFInd? [Y/n]:${RESET} " REFIND_ANSWER
  REFIND_ANSWER=${REFIND_ANSWER:-y}
fi

# Copy hardware-configuration.nix to ~/.dotfiles/nixos hosts dir
[ -f "/etc/nixos/hardware-configuration.nix" ] && \
  sudo cp -f \
    "/etc/nixos/hardware-configuration.nix" \
    "$HOME/.dotfiles/nixos/hosts/$HOST/hardware-configuration.nix"

echo
echo -e "${GREEN}Updating Nix flake...${RESET}"
nix --extra-experimental-features "nix-command flakes" \
  flake update --flake "$DOTFILES_DIR/nixos"

echo
echo -e "${GREEN}Applying system configuration...${RESET}"
sudo nixos-rebuild switch --flake "$DOTFILES_DIR/nixos#$HOST"

echo
echo -e "${GREEN}Applying dotfiles with chezmoi...${RESET}"
chezmoi init --apply "$DOTFILES_DIR" --force

echo
echo -e "${GREEN}Setting user directories...${RESET}"
"$HOME/scripts/update-user-dirs.sh"

echo
# Enable/disable autounlock for LUKS with TPM
"$HOME/scripts/luks-tpm-autounlock.sh" --hostname "$HOST"

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
read -rp "Do you want to reboot now? [Y/n]: " REBOOT_ANSWER
REBOOT_ANSWER=${REBOOT_ANSWER:-y}

case "$REBOOT_ANSWER" in
  [yY]|[yY][eE][sS])
    [ -d "$HOME/rEFI2nd" ] && rm -rf "$HOME/rEFI2nd"
    [ -d "/etc/nixos" ] && sudo rm -rf "/etc/nixos"
    sudo reboot;;
esac