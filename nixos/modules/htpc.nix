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
  # uiScale is the one knob that has to differ per machine: the theme's
  # defaults are sized for taylorpc's 1440x900 initrd framebuffer, and these
  # boxes hand off to a TV. Check what the initrd actually gets with
  # `cat /sys/class/graphics/fb0/modes` and tune against a real boot -- 2.0
  # is the starting guess for a 4K mode, 1.0 if the firmware hands over 1080p.
  myOptions.plymouth = {
    enable = true;
    theme = "minimal";
    themePackages = [
      (pkgs.callPackage ../pkgs/plymouth-theme-minimal/package.nix
        (splashLogo // {
          uiScale = 2.0;

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