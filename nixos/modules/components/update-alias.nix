{ pkgs, ... }:

let
  update-alias = pkgs.writeShellApplication {
    name = "update";
    runtimeInputs = with pkgs; [ git nix nixos-rebuild coreutils nettools ];
    text = ''
      dotfiles="''${DOTFILES:-$HOME/.dotfiles}"
      host="$(hostname)"

      git -C "$dotfiles" pull --rebase --autostash
      git -C "$dotfiles" add --intent-to-add -f \
        "nixos/hosts/$host/hardware-configuration.nix" 2>/dev/null || true
      nix flake update --flake "$dotfiles/nixos"
      sudo nixos-rebuild switch --flake "$dotfiles/nixos#$host"
    '';
  };
in
{
  environment.systemPackages = [ update-alias ];
}