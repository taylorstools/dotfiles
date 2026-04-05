{ config, pkgs, lib, ... }:

{
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

  environment.systemPackages = with pkgs; [
    hyprlock
  ];
}