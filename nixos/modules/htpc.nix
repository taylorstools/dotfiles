{ pkgs, ... }:

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

  #region boot splash
  # The same minimal theme taylorpc uses, from the same logo definition, so
  # the HTPCs look like the rest of the fleet on the way up.
  #
  # uiScale is the one knob that has to differ per machine. The theme's
  # defaults are design units against taylorpc's 1440x900 initrd
  # framebuffer, where the 230-unit field is 16% of the screen width. These
  # boxes get a 4K framebuffer and are read from a couch rather than from
  # 60cm, so bare parity (~2.7) is the floor rather than the target: 3.0
  # puts the field at ~18% of a 3840px screen. Halve it if the firmware
  # turns out to hand the initrd 1080p -- check the early-boot framebuffer
  # line, not /sys/class/graphics/fb0, which is whatever the GPU driver set
  # later.
  myOptions.plymouth = {
    enable = true;
    theme = "minimal";
    themePackages = [
      (pkgs.callPackage ../pkgs/plymouth-theme-minimal/package.nix
        (splashLogo // {
          uiScale = 3.0;

          # ~15s at the ~50 ticks/sec refresh() actually runs at. Long enough
          # that a clevis unlock (~12s, most of it wait-online) answers the
          # request before the field is ever drawn, so a normal boot shows
          # only the spinner and the prompt appears solely when the network
          # unlock did not happen. Typing reveals it immediately regardless.
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
}