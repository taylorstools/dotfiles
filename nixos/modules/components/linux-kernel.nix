{ config, lib, pkgs, ... }:

let
  cfg = config.myOptions.linuxKernel;

  zfsCompatibleKernelPackages = lib.filterAttrs
    (name: kernelPackages:
      builtins.match "linux_[0-9]+_[0-9]+" name != null
      && (builtins.tryEval kernelPackages).success
      && (
        let
          usable = builtins.tryEval (!kernelPackages.${zfsModuleAttribute}.meta.broken);
        in
        usable.success && usable.value
      ))
    pkgs.linuxKernel.packages;

  candidates = lib.sort
    (a: b: lib.versionOlder a.kernel.version b.kernel.version)
    (builtins.attrValues zfsCompatibleKernelPackages);

  latestZfsCompatible =
    if candidates == [ ]
    then throw ''
      myOptions.linuxKernel: no linux_X_Y kernel in this nixpkgs has a usable
      ${zfsModuleAttribute} module. This normally means nixpkgs moved ahead of
      OpenZFS; switch myOptions.linuxKernel.variant back to "lts" until it
      catches up.
    ''
    else lib.last candidates;

  selected = {
    lts = pkgs.linuxPackages;
    latest-zfs = latestZfsCompatible;
  }.${cfg.variant};
in
{
  options.myOptions.linuxKernel.variant = lib.mkOption {
    type = lib.types.enum [ "lts" "latest-zfs" ];
    default = "lts";
    example = "latest-zfs";
    description = ''
      Which kernel series this host tracks.

      "lts" uses pkgs.linuxPackages, the nixpkgs default kernel, which upstream
      keeps pinned to a longterm series. This is what a host gets with no
      boot.kernelPackages set at all, so it is the do-nothing option: fewest
      surprises, longest support window, and ZFS support is never in question.

      "latest-zfs" walks every linux_X_Y attribute in nixpkgs, drops the ones
      whose OpenZFS module is marked broken, and takes the highest version left
      -- the newest mainline kernel that ZFS can actually build against.
      Everything it selects is a stock nixpkgs kernel, so it comes from the
      binary cache rather than compiling locally, and it moves forward on its
      own whenever the nixpkgs input is bumped. Worth it for new hardware or a
      driver fix that has not reached longterm yet; it also means more frequent
      kernel rebuilds and a shorter tested trail.

      Both options stay on the stable OpenZFS release. zfs_unstable is
      deliberately not offered, which is what caps how far "latest-zfs" can go.
    '';
  };

  config.boot.kernelPackages = lib.mkDefault selected;
}
