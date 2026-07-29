{ config, pkgs, inputs, ... }:

{
  assertions = [{
    assertion = config.myOptions.amd.rocm.enable;
    message = "davinci-resolve requires myOptions.amd.rocm.enable = true";
  }];

  environment.systemPackages = [
    inputs.davinci-resolve.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}