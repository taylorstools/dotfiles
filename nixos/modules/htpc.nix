{ config, lib, pkgs, ... }:

let
  splashLogo = import ./components/assets/splash-logo.nix;
in
{
  imports = [
    ./components/dim-overlay
    ./components/kde-plasma.nix
    ./components/sddm-autologin.nix
    ./components/ventoy-backup.nix
    ./components/xbox-controller.nix
  ];

  options.myOptions.htpc.splashScale = lib.mkOption {
    type = lib.types.either lib.types.int lib.types.float;
    default = 3.0;
    description = ''
      uiScale handed to the minimal Plymouth theme on this host. It depends
      entirely on the framebuffer the firmware hands the initrd, which is not
      necessarily the panel's native mode, so it is set per host rather than
      guessed from the display.
    '';
  };

  # Declaring an option above forces everything else under an explicit
  # `config`; the module system rejects the two mixed at the top level.
  config = {
    #region boot splash
    # The same minimal theme taylorpc uses, from the same logo definition, so
    # the HTPCs look like the rest of the fleet on the way up.
    #
    # The scale is per host: see myOptions.htpc.splashScale above.
    myOptions.plymouth = {
      enable = true;
      theme = "minimal";
      themePackages = [
        (pkgs.callPackage ../pkgs/plymouth-theme-minimal/package.nix
          (splashLogo // {
            uiScale = config.myOptions.htpc.splashScale;

            # ~15s at the ~50 ticks/sec refresh() actually runs at. Long
            # enough that a clevis unlock (~12s, most of it wait-online)
            # answers the request before the field is ever drawn, so a normal
            # boot shows only the spinner and the prompt appears solely when
            # the network unlock did not happen. Typing reveals it
            # immediately regardless.
            passwordRevealTicks = 750;
          }))
      ];
    };
    #endregion

    programs = {
      steam.enable = true;
      dim-overlay.enable = true;
      kdeconnect.enable = true;
    };

    environment.systemPackages = with pkgs; [
      easyeffects
      jellyfin-desktop
    ];
  };
}
