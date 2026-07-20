{ pkgs, lib, ... }:

{
  imports = [
    ./ydotool.nix
  ];

  services.greetd = {
    enable = true;

    settings = {
      terminal = {
        vt = lib.mkForce 8;
      };

      initial_session = {
        command = "niri-session";
        user = "taylor";
      };

      default_session = {
        command = "niri-session";
        user = "taylor";
      };
    };
  };

  security.pam.services.hyprlock.enableGnomeKeyring = true;

  environment.systemPackages = with pkgs; [
    hyprlock
  ];
}