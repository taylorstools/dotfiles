{ pkgs, ... }:

let
  clean-alias = pkgs.writeShellApplication {
    name = "clean";
    runtimeInputs = with pkgs; [ gum nix ];
    text = ''
      set -euo pipefail

      gum log --level info "Deleting old system generations and collecting garbage..."
      sudo nix-collect-garbage -d

      gum log --level info "Deleting old user profile generations..."
      nix-collect-garbage -d

      gum log --level info "Rewriting boot entries for the current generation..."
      sudo /run/current-system/bin/switch-to-configuration boot

      gum log --level info "Optimising the nix store..."
      sudo nix-store --optimise

      gum log --level info "Done."
    '';
  };
in
{
  environment.systemPackages = [ clean-alias ];
}
