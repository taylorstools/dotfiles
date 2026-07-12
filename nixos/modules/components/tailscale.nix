{ pkgs, ... }:

let
  username = "taylor";
in
{
  services.tailscale = {
    enable = true;
    extraSetFlags = [ "--operator=${username}" ];
    useRoutingFeatures = "client";
  };

  environment.systemPackages = with pkgs; [
    trayscale
  ];
}