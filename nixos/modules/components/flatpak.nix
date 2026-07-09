{ inputs, pkgs, ... }:

{
  imports = [ inputs.nix-flatpak.nixosModules.nix-flatpak ];

  services.flatpak = {
    enable = true;

    remotes = [{
      name = "flathub";
      location = "https://flathub.org/repo/flathub.flatpakrepo";
    }];

    packages = [ "com.thincast.client" ];

    uninstallUnmanaged = false;
    update.onActivation = false;
  };
}