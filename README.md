# Dotfiles

Dotfiles for my NixOS systems, managed by [chezmoi](https://github.com/twpayne/chezmoi).

## Installation

Boot into a minimal NixOS ISO, connect to Wi-Fi with `nmtui` if needed, then run this command to install the base system:

```sh
nix run github:taylorstools/dotfiles?dir=nixos#install --extra-experimental-features "nix-command flakes"
```

This will ask you to select a drive for your NixOS system to be installed to. If `taylorpc` is selected as the host, the script will ask you if you plan on dual-booting on the drive. If you say yes, it will then prompt you either for the size of the Linux partition you want to create, so you can install Windows to the unallocated space later, or ask if you want to install NixOS to existing unallocated space on the drive. If the former, it wipes the drive and creates the Linux partition to be the size you specified. If the latter, it installs NixOS to the unallocated space without deleting any other partitions. And if you selected a host other than `taylorpc`, the entire drive is wiped and used for NixOS. Before making any changes to the drive, the installation script also gives you a chance to review `disko.nix`, so you can make any adjustments as needed.

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

## Verify Secure Boot

After you reboot, verify the state of Secure Boot on your system:

```sh
~ > sbctl status
Installed:	✓ sbctl is installed
Owner GUID:	3d950534-810e-4350-80a6-2b1a65ef4bef
Setup Mode:	✓ Disabled
Secure Boot:	✓ Enabled
Vendor Keys:	microsoft
```

If Secure Boot is enabled, you are good.

## LUKS unlock at boot

Every host encrypts its root with LUKS2. How you get past that at boot differs by machine, deliberately:

| Host | Unlock | Why |
| --- | --- | --- |
| `livingroompc`, `bedroompc` | TPM2 auto-unlock (PCR 0+7) | HTPCs across the room; typing a passphrase on a media box is impractical |
| `taylorpc` | Passphrase at a Plymouth prompt | A laptop that leaves the house, so the disk should not open itself |

A fresh install always starts with auto-unlock **off**. The post-install script seeds `/etc/nixos/luks-tpm-autounlock.nix` in that state, because no TPM keyslot exists yet. On `taylorpc` that is the final state and there is nothing more to do — the graphical passphrase prompt comes from the `minimal` Plymouth theme in `nixos/pkgs/plymouth-theme-minimal`, enabled through `myOptions.plymouth`.

### Enabling TPM auto-unlock

Do this only **after** `sbctl enroll-keys` and a reboot. Enrolling Secure Boot keys changes PCR 7, and a TPM keyslot bound to the old PCR 7 stops working the moment it does. The same applies later: firmware updates and any further key changes invalidate the enrolment, and you fall back to the passphrase until you re-run this.

```sh
"$HOME/scripts/luks-tpm-autounlock.sh" --hostname "$(hostname)" --enable
```

Reboot when it finishes; the drive should unlock without a prompt.

The script always changes the LUKS header and the NixOS config **together** — enrolling or wiping the TPM keyslot as well as flipping the crypttab option. Letting those drift is how you end up with an initrd asking a TPM that holds no keyslot: it stalls, fails, then prompts, with the reason hidden behind `quiet`, so it just looks like a slow boot.

Other flags:

```sh
--status         # report header state vs config state; changes nothing
--disable        # wipe the TPM keyslot and go back to the passphrase
--device <path>  # skip the device chooser
--keep-slot      # with --disable, leave the keyslot in the header
--norebuild      # write config, skip nixos-rebuild
--yes            # assume yes, for unattended runs
```

`--status` is the first thing to run when auto-unlock stops behaving; it names the drift in either direction.

The script refuses to leave a disk that only the TPM can open, and backs the LUKS header up to `~/luks-header-backups/` before any destructive change. Move those backups off the machine — a header file plus your passphrase decrypts the disk.

## Per-host configuration files

Four files are owned by `/etc/nixos`. The dotfiles repo only holds a copy:

- `hardware-configuration.nix`
- `hostid.nix`
- `disko.nix`
- `luks-tpm-autounlock.nix`

The `update` alias and the autoupgrade service both copy `/etc/nixos` over the repo copy immediately before every rebuild. **Editing the repo copy by hand does not survive** — the next rebuild overwrites it and commits the overwrite. Change these through `/etc/nixos`, or for the LUKS module through `luks-tpm-autounlock.sh`, which writes both.
