{ ... }:

{
  networking.firewall.allowedTCPPorts = [ 3389 ];

  environment.systemPackages = with pkgs; [
    kdePackages.krdp
  ];
}