{ pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  boot.initrd.systemd.enable = true;
  boot.initrd.availableKernelModules =
    [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];

  hardware.enableRedistributableFirmware = true;
  nixpkgs.hostPlatform = "x86_64-linux";

  networking.hostName = "@HOSTNAME@";
  networking.hostId   = "@HOSTID@";         # required by ZFS
  networking.networkmanager.enable = true;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
    settings.PermitRootLogin = "no";
  };

  time.timeZone = "America/Phoenix";
  i18n.defaultLocale = "en_US.UTF-8";

  users.mutableUsers = true;
  users.users.taylor = {
    isNormalUser = true;
    extraGroups  = [ "wheel" "networkmanager" ];
    hashedPasswordFile = "/etc/users/taylor.hash";
  };

  environment.systemPackages = with pkgs; [
    chezmoi
    dconf
    git
    gum
    python3
    xdg-user-dirs
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  security.sudo.wheelNeedsPassword = false;

  services.zfs.autoScrub.enable = true;

  system.stateVersion = "25.11";
}