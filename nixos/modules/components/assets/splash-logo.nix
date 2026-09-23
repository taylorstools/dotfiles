# The logo shared by the Plymouth theme and the niri splash, and now by the
# HTPCs' Plymouth too. One definition so the mark cannot drift between the
# places it is drawn. Consumers pass this straight into
# pkgs/plymouth-theme-minimal/package.nix (and niri-splash takes the same
# three attributes).
{
  logo = ./nixos-logo.svg;
  logoWidth = 112;
  logoGap = 60;
}
