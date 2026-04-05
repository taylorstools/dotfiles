{ config, pkgs, ... }:

{  
  # Printing
  services.printing.enable = true;
  services.printing.drivers = [ pkgs.hplip ];

  # Scanning
  hardware.sane.enable = true;
  hardware.sane.extraBackends = [ pkgs.hplipWithPlugin ];

  # Automatic discovery
  services.avahi.enable = true;
  services.avahi.nssmdns4 = true;
  services.avahi.openFirewall = true;
}