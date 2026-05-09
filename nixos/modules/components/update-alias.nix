{ pkgs, ... }:

let
  update-alias = pkgs.writeShellApplication {
    name = "update";
    runtimeInputs = with pkgs; [ coreutils git gum nix nixos-rebuild ];
    text = ''
      set -euo pipefail

      DOTFILES="''${DOTFILES:-$HOME/.dotfiles}"
      HWCONFIG="/etc/nixos/hardware-configuration.nix"
      DEST="$DOTFILES/nixos/hosts/$(hostname)/hardware-configuration.nix"

      gum log --level info "Pulling latest dotfiles..."
      git -C "$DOTFILES" pull --rebase --autostash

      if [ -f "$HWCONFIG" ]; then
        gum log --level info "Copying $HWCONFIG to $DEST..."
        cp -f "$HWCONFIG" "$DEST"
      else
        gum log --level error "$HWCONFIG does not exist!"
        exit 1
      fi

      git -C "$DOTFILES" add -f "nixos/hosts/$(hostname)/hardware-configuration.nix"

      gum log --level info "Updating flake..."
      nix flake update --flake "$DOTFILES/nixos"

      gum log --level info "Rebuilding system configuration..."
      sudo nixos-rebuild switch --flake "$DOTFILES/nixos#$(hostname)"
    '';
  };
in
{
  environment.systemPackages = [ update-alias ];
}