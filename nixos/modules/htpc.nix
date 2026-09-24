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
    default = 1.5;
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

            # A clevis unlock lands around 12s, most of it wait-online, so
            # 15 leaves a little margin without leaving someone staring at a
            # black screen when the network genuinely is not there. The tick
            # backstop is deliberately far longer: it is only meant to fire
            # if Plymouth never reports boot progress at all.
            passwordRevealSeconds = 15;
            passwordRevealTicks = 4000;

            # Nothing but the logo until the disk resolves one way or the
            # other -- see spinnerBeforeUnlock in package.nix.
            spinnerBeforeUnlock = false;
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
