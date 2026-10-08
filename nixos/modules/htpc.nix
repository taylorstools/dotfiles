{ config, lib, pkgs, ... }:

let
  splashLogo = import ./components/assets/splash-logo.nix;

  # How this host's root volume unlocks, read off the config that does the
  # unlocking rather than restated per host, so the splash follows along when
  # a crypttab TPM option or clevis-tang.nix is switched on or off.
  luksOpts = lib.concatMap (d: d.crypttabExtraOpts)
    (lib.attrValues config.boot.initrd.luks.devices);
  tpmUnlock = lib.any (lib.hasPrefix "tpm2-device=") luksOpts;
  # The option only exists on hosts that import clevis-tang.nix.
  clevisUnlock = config.myOptions.clevisTang.enable or false;
in
{
  imports = [
    ./components/dim-overlay
    ./components/kde-plasma.nix
    ./components/reset-bluetooth-state.nix
    ./components/sddm-autologin.nix
    ./components/ventoy-backup.nix
    ./components/xbox-controller.nix
  ];

  options.myOptions.htpc.passwordRevealSeconds = lib.mkOption {
    type = lib.types.ints.unsigned;
    default = if clevisUnlock then 15 else 0;
    defaultText = lib.literalExpression "if clevisTang.enable then 15 else 0";
    description = ''
      Seconds the splash holds the passphrase field back while Clevis tries
      to unlock, counted from when Plymouth starts. Set it past the host's
      usual unlock time so the field does not flash up just before the disk
      opens. Typing reveals it at once regardless, so a longer hold only
      costs time when the network is genuinely down and nobody touches the
      keyboard.
    '';
  };

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
    # the HTPCs look like the rest of the fleet on the way up. What shows
    # before the disk opens depends on how it opens; see below.
    #
    # The scale is per host: see myOptions.htpc.splashScale above.
    myOptions.plymouth = {
      enable = true;
      theme = "minimal";
      themePackages = [
        (pkgs.callPackage ../pkgs/plymouth-theme-minimal/package.nix
          (splashLogo // {
            uiScale = config.myOptions.htpc.splashScale;

            # Clevis (both HTPCs): black while it tries, for
            # myOptions.htpc.passwordRevealSeconds (above). The tick
            # backstop is deliberately far longer: it is only meant to fire
            # if Plymouth never reports boot progress at all. Without clevis
            # there is nothing to wait for, so the field comes up when asked.
            passwordRevealSeconds = config.myOptions.htpc.passwordRevealSeconds;
            # Kept well past the seconds hold at any plausible tick rate.
            passwordRevealTicks =
              if clevisUnlock
              then lib.max 4000 (config.myOptions.htpc.passwordRevealSeconds * 200)
              else 0;

            # TPM2: nothing to wait on, so logo and spinner from
            # the first frame. A failed TPM unlock still gets the field,
            # at once, in the spinner's place under the logo.
            showAtStart = tpmUnlock && !clevisUnlock;
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
