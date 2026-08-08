{ pkgs, ... }:

let
  username = config.myOptions.user.name;
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