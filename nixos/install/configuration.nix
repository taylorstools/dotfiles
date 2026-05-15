{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # --- Boot --------------------------------------------------------------
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  boot.initrd.systemd.enable = true;
  boot.initrd.availableKernelModules =
    [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];

  # --- Hardware ----------------------------------------------------------
  hardware.enableRedistributableFirmware = true;
  nixpkgs.hostPlatform = "x86_64-linux";

  # --- Networking --------------------------------------------------------
  networking.hostName = "@HOSTNAME@";
  networking.hostId   = "@HOSTID@";     # required by ZFS
  networking.networkmanager.enable = true;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
    settings.PermitRootLogin = "no";
  };

  # --- Time / locale -----------------------------------------------------
  time.timeZone = "America/Phoenix";
  i18n.defaultLocale = "en_US.UTF-8";

  # --- User --------------------------------------------------------------
  users.mutableUsers = true;
  users.users.taylor = {
    isNormalUser = true;
    extraGroups  = [ "wheel" "networkmanager" ];
    initialPassword = "changeme";       # change immediately
  };

  # --- Tooling for postinstall (bootstrap.sh) ----------------------------
  environment.systemPackages = with pkgs; [ git gum chezmoi vim ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  security.sudo.wheelNeedsPassword = false;   # full config tightens this

  services.zfs.autoScrub.enable = true;

  system.stateVersion = "25.05";
}