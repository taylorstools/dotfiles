{ pkgs, ... }:

{  
  # Printing
  services.printing = {
    enable = true;
    drivers = [ pkgs.hplip ];
  };

  # Scanning
  hardware.sane = {
    enable = true;
    extraBackends = [ pkgs.hplipWithPlugin ];
  };

  # Automatic discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
}