{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.myOptions.davinci;

  # Resolve needs a GPU compute backend: CUDA on Nvidia, OpenCL/ROCm on AMD.
  # Intel iGPUs are not a supported target on Linux.
  hasCuda = builtins.elem config.myOptions.nvidia.mode [ "proprietary" "open" ];
  hasRocm = config.myOptions.amd.rocm.enable;
in
{
  options.myOptions.davinci.enable =
    lib.mkEnableOption "DaVinci Resolve (requires a CUDA- or ROCm-capable GPU)";

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = hasCuda || hasRocm;
      message = ''
        myOptions.davinci.enable requires a GPU compute backend. Set either
        myOptions.amd.rocm.enable = true, or myOptions.nvidia.mode to
        "proprietary" or "open".
      '';
    }];

    environment.systemPackages = [
      inputs.davinci-resolve.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];

    # The input lives on the home Forgejo (git.lan), not GitHub. nix.gc does
    # not treat flake input sources as roots, and once this one is collected,
    # evaluating the flake has to fetch it again, which fails the whole
    # rebuild whenever git.lan is out of reach. Root it in the system closure.
    # This belongs here rather than in autoupgrade.nix: rooting it on hosts
    # that do not use Resolve makes their evaluation fetch it too.
    system.extraDependencies = [ inputs.davinci-resolve.outPath ];
  };
}
