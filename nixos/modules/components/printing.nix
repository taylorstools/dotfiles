{ pkgs, ... }:

let
  # hplip's Qt5 GUI tools (hp-toolbox, the graphical hp-setup) pull in pyqt5,
  # which no longer builds: PyQt5 5.15.10 predates Python 3.14's ABI v12 and
  # the binding generator refuses. Nothing here needs those tools — the CUPS
  # drivers and SANE backends are independent of them — so build without Qt.
  # The CLI equivalents (hp-setup -i, hp-info, hp-check) are still present.
  #
  # One build serves both CUPS and SANE. The plugin variant is unfree, so it
  # is never in cache.nixos.org and always builds locally; a separate
  # plugin-less build for CUPS was a second full hplip compile on every
  # nixpkgs bump. The plugin only adds the proprietary bits some HP models
  # need; the CUPS drivers are the same otherwise.
  hplipWithPlugin = pkgs.hplip.override {
    withQt5 = false;
    withPlugin = true;
  };
in
{
  # Printing
  services.printing = {
    enable = true;
    drivers = [ hplipWithPlugin ];
  };

  # Scanning
  hardware.sane = {
    enable = true;
    extraBackends = [ hplipWithPlugin ];
  };

  # Automatic discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
}
