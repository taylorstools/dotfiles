{ config, lib, pkgs, ... }:

let
  cfg = config.myOptions.linuxKernel;

  zfsCompatibleKernelPackages = lib.filterAttrs
    (name: kernelPackages:
      builtins.match "linux_[0-9]+_[0-9]+" name != null
      && (builtins.tryEval kernelPackages).success
      && (
        let
          usable = builtins.tryEval (!kernelPackages.zfs.meta.broken);
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
      zfs module. This normally means nixpkgs moved ahead of OpenZFS; switch
      myOptions.linuxKernel.variant back to "lts" until it catches up.
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

      "latest-zfs" walks every linux_X_Y attribute in nixpkgs, keeps the ones
      whose stable OpenZFS module is not marked broken, and takes the highest
      version left -- the newest mainline kernel that ZFS can actually build
      against. tryEval guards attributes that throw when forced, so a kernel
      past end-of-life or unsupported on this platform cannot fail evaluation.
      Everything selected is a stock nixpkgs kernel, so it comes from the
      binary cache rather than compiling locally, and it moves forward on its
      own whenever the nixpkgs input is bumped.

      zfs_unstable is deliberately not offered, so the stable OpenZFS release
      is what caps how far "latest-zfs" can climb.

      The value is applied with mkDefault, so a host can override
      boot.kernelPackages directly without mkForce. Note that "latest-zfs" can
      outrun the proprietary Nvidia driver: on a host with
      myOptions.nvidia.mode = "proprietary" or "open", a build failure in the
      Nvidia module usually means switching hardware.nvidia.package to .beta
      or .production.
    '';
  };

  config.boot.kernelPackages = lib.mkDefault selected;
}
