{ config, lib, pkgs, ... }:

let
  splashLogo = import ./components/assets/splash-logo.nix;

  # How this host's root volume unlocks, read off the config that does the
  # unlocking rather than restated per host, so the splash follows along when
  # scripts/luks-tpm-autounlock.sh or clevis-tang.nix is switched on or off.
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

            # Clevis (livingroompc): black while it tries. An unlock lands
            # around 12s, most of it wait-online, so holding the field back
            # 15s leaves a little margin without leaving someone staring at a
            # black screen when the network genuinely is not there. The tick
            # backstop is deliberately far longer: it is only meant to fire
            # if Plymouth never reports boot progress at all. Without clevis
            # there is nothing to wait for, so the field comes up when asked.
            passwordRevealSeconds = if clevisUnlock then 15 else 0;
            passwordRevealTicks = if clevisUnlock then 4000 else 0;

            # TPM2 (bedroompc): nothing to wait on, so logo and spinner from
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
