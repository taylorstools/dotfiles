# Dotfiles

Dotfiles for my NixOS systems, managed by [chezmoi](https://github.com/twpayne/chezmoi).

## Installation

Boot into a minimal NixOS ISO, connect to Wi-Fi with `nmtui` if needed, then run this command to install the base system:

```sh
nix run github:taylorstools/dotfiles?dir=nixos#install --extra-experimental-features "nix-command flakes"
```

This will ask you to select an entire drive for your NixOS system, which it will then wipe. If `taylorpc` is selected as the host, the script will ask you if you plan on dual-booting and, if affirmative, prompt you for the size of the Linux partition to create, so you can install Windows to the unallocated space later. Before erasing the drive, the installation script also gives you a chance to review `disko.nix`, so you can make any changes as needed.

Once the installation finishes, boot into the new system and log in with the credentials you set previously. Connect to Wi-Fi again with `nmtui` if needed, then run the post-install script:

```sh
nix run github:taylorstools/dotfiles?dir=nixos#postinstall
```

When the post-install script is complete, you will see a message that asks if you want to power down the system, so that you can enable Secure Boot.

## Secure Boot

The post-install script prepares the system for Secure Boot with [Lanzaboote](https://github.com/nix-community/lanzaboote). After the post-install script runs and powers down your system, go into your BIOS setup to enable Secure Boot. Steps vary by manufacturer.

### HP

1. Mash F10 to get into BIOS.
2. Security tab > BIOS Sure Start > Disable "Sure Start Secure Boot Keys Protection".
3. Security tab > Create BIOS Administrator Password. Go through the steps to create a BIOS admin password.
4. Security tab > Secure Boot Configuration > Enable "Secure Boot".

Save and exit. HP may ask you to type in a 4 digit number for authorization. Do that, then immediately boot back into the BIOS:

1. Security tab > Secure Boot Configuration > Enable "Clear Secure Boot keys"
2. Security tab > Secure Boot Configuration > Enable "Enable MS UEFI CA key"

Then save and exit. Enter the 4 digit PIN from HP for authorization, and then your system should boot into NixOS without any issues.

### Asus

1. Mash F2 to get into BIOS.
2. Press the "Advanced Settings" button in the corner or press F7 to jump right into it.
3. Security tab > Secure Boot > set "Secure Boot Control" to Enabled.
4. Security tab > Secure Boot > Expert Key Management > Reset to Setup Mode.

Then save and exit, your system should boot into NixOS without any issues.

### Other Manufacturers

Refer to Lanzaboote's documentation for steps on enabling Secure Boot if you are trying to do this on another computer: [Enable Secure Boot](https://nix-community.github.io/lanzaboote/getting-started/enable-secure-boot.html).

### Enroll Keys in NixOS

After enabling Secure Boot, your system should boot into NixOS. Open a terminal and enroll keys:

```sh
sudo sbctl enroll-keys --microsoft
```

Then reboot.

## Verify Secure Boot and auto-unlock LUKS with TPM

After you reboot, verify the state of Secure Boot on your system:

```sh
~ > sbctl status
Installed:	✓ sbctl is installed
Owner GUID:	3d950534-810e-4350-80a6-2b1a65ef4bef
Setup Mode:	✓ Disabled
Secure Boot:	✓ Enabled
Vendor Keys:	microsoft
```

If it is enabled, then you are good! You can now move on to enabling your LUKS encrypted drive to be auto-unlocked at boot by the TPM:

```sh
"$HOME/scripts/luks-tpm-autounlock.sh" --hostname $HOSTNAME
```

Run through the steps in the script, and when it's complete, reboot. You should no longer be prompted for a password to unlock your LUKS encrypted drive.