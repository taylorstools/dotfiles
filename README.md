# Dotfiles

Dotfiles for my NixOS systems, managed by [chezmoi](https://github.com/twpayne/chezmoi).

## Installation

Boot into a minimal NixOS ISO, connect to Wi-Fi with `nmtui` if needed, then run this command to install the base system:

```sh
nix run github:taylorstools/dotfiles?dir=nixos#install --extra-experimental-features "nix-command flakes"
```

This will ask you to select a drive for your NixOS system to be installed to. If `taylorpc` is selected as the host, the script will ask you if you plan on dual-booting on the drive. If you say yes, it will then prompt you either for the size of the Linux partition you want to create, so you can install Windows to the unallocated space later, or ask if you want to install NixOS to existing unallocated space on the drive. If the former, it wipes the drive and creates the Linux partition to be the size you specified. If the latter, it installs NixOS to the unallocated space without deleting any other partitions. And if you selected either of the HTPCs, the entire drive is wiped and used for NixOS. Before making any changes to the drive, the installation script also gives you a chance to review `disko.nix`, so you can make any adjustments as needed.

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
| `taylorpc` | Passphrase at a Plymouth prompt | Laptop that leaves the house, so the disk should not open itself |

A fresh install always starts with auto-unlock **off**. The post-install script seeds `/etc/nixos/luks-tpm-autounlock.nix` in that state, because no TPM keyslot exists yet. On the laptop that is the final state and there is nothing more to do. The graphical passphrase prompt comes from the `minimal` Plymouth theme in `nixos/pkgs/plymouth-theme-minimal`, enabled through `myOptions.plymouth`.

### Enabling TPM auto-unlock

This is for the HTPCs. Do not run `--enable` on `taylorpc`: auto-unlocking a laptop that leaves the house defeats the point of encrypting it, because anyone who powers it on gets a decrypted disk and, with autologin, a live session. `--status` and `--disable` still apply there.

Do this only **after** `sbctl enroll-keys` and a reboot. Enrolling Secure Boot keys changes PCR 7, and a TPM keyslot bound to the old PCR 7 stops working the moment it does. The same applies later: firmware updates and any further key changes invalidate the enrollment, and you fall back to the passphrase until you re-run this.

```sh
"$HOME/scripts/luks-tpm-autounlock.sh" --hostname "$(hostname)" --enable
```

Reboot when it finishes; the drive should unlock without a prompt.

The script always changes the LUKS header and the NixOS config **together**: it enrolls or wipes the TPM keyslot as well as flipping the crypttab option. Letting those drift is how you end up with an initrd asking a TPM that holds no keyslot: it stalls, fails, then prompts, with the reason hidden behind `quiet`, so it just looks like a slow boot.

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

The script refuses to leave a disk that only the TPM can open, and backs the LUKS header up to `~/luks-header-backups/` before any destructive change. Move those backups off the machine. A header file plus your passphrase decrypts the disk.

## Manual Post-Install Steps

What is left once the system is otherwise finished, meaning Secure Boot keys enrolled and, on the HTPCs, TPM auto-unlock on. Each of these is state no rebuild can produce: enrollment data, credentials and pairings that live outside both the Nix store and chezmoi, so a reinstall starts with none of it.

### Howdy face enrollment

`taylorpc` only.

`myOptions.howdy` sets up the daemon, the PAM opt-in for hyprlock and camera group access. It cannot supply your face. Enrolled models live in `/var/lib/howdy/models/<user>.dat`, which a reinstall takes with it.

Confirm the IR sensor first. `devicePath` names a bare `/dev/videoN` node, and those are handed out in probe order, so the number can move on a fresh install:

```sh
ls -l /dev/v4l/by-path/         # the IR sensor, not the RGB one
sudo howdy -U taylor test       # live view; a detected face gets boxed
```

If it moved, point `myOptions.howdy.devicePath` at the matching `/dev/v4l/by-path/...` path rather than chasing the new number.

Then enroll, three or four times:

```sh
sudo howdy -U taylor add        # repeat: straight on, angled, closer, further back
sudo howdy -U taylor list
```

One model is not enough. Howdy matches against the smallest distance across every enrolled model, and a single model from a grayscale IR sensor sits close enough to the threshold that ordinary variation (head turned, sitting further back) is rejected. Adding models is the fix for that. Raising `certainty` is letting other faces in to solve a problem only your own face has.

Failure is quiet by design: `pam_howdy`'s output goes to hyprlock, which swallows it, and "Failure, timeout reached" covers both "never saw a face" and "saw one that never matched". To watch an attempt with its output attached to a terminal, add `"su"` to `myOptions.howdy.services`, rebuild, and run `su - taylor`.

### Login keyring

`taylorpc` only. The HTPCs authenticate against KWallet under Plasma, and gnome-keyring is not enabled there at all.

`services.gnome.gnome-keyring.enable` in `niri.nix` also turns on `security.pam.services.login.enableGnomeKeyring`, and `login` is the *console* PAM service. The graphical session comes up through greetd, whose stack has no `pam_gnome_keyring` in it, so nothing hands the daemon a password at login. Any keyring that has a password is therefore a prompt you answer by hand, every session, forever. A single TTY login as `taylor` is enough to create one holding the account password.

The fix is a login keyring with an empty password, which the daemon opens by itself:

```sh
ls ~/.local/share/keyrings/
rm -f ~/.local/share/keyrings/login.keyring ~/.local/share/keyrings/user.keystore
```

Log out and back in. The next application to ask for the secret service triggers a prompt to create the keyring; on these hosts that is Claude Desktop, which `myOptions.claude-desktop.passwordStore` puts on `gnome-libsecret`. Leave both password fields blank and confirm the unsafe-storage warning.

To reset an existing keyring instead of deleting it:

```sh
nix run nixpkgs#seahorse     # right-click Login > Change Password, leave the new one blank
```

The trade is real but small here: an empty password means the keyring is encrypted with nothing, so anything that can read your home directory can read your tokens. That is the bargain autologin already struck. On these hosts the LUKS passphrase at boot is the authentication boundary, and hyprlock is what guards the session after it.

### KWallet

`livingroompc` and `bedroompc` only. There is no gnome login keyring on those hosts; `kdewallet` is the secret store Chrome, NetworkManager and the portals use.

Same structural problem as above with a different daemon. `services.desktopManager.plasma6.enable` wires `pam_kwallet` into the `login` and `kde` PAM services, the console login and the screen locker. Neither runs when SDDM logs you in automatically, and no password is typed for PAM to pass on, so nothing unlocks the wallet at session start.

On a fresh install the first thing to touch the wallet raises the KWallet wizard, whether that is Chrome storing its Safe Storage key or NetworkManager saving a PSK. Take the **no password** option. A wallet with a password means a prompt at every boot on a machine driven by a remote from the couch, and no way to answer it from there.

If a wallet already exists holding your account password, which one TTY login or one screen unlock is enough for `pam_kwallet` to have created, start it over:

```sh
rm ~/.local/share/kwalletd/kdewallet.kwl ~/.local/share/kwalletd/kdewallet.salt
```

Log out and back in, then let the wizard run and leave the password empty.

To check which state a wallet is in, force it shut and reopen it from a terminal on the machine itself:

```sh
QD=$(command -v qdbus6 || command -v qdbus)
"$QD" org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close kdewallet true
"$QD" org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open kdewallet 0 test
```

A handle straight back means no password. A dialog means there is one.

Be clear about what blank buys and costs here. These two hosts TPM-auto-unlock at boot and then autologin, so a wallet that opens itself is the last of three doors already standing open: anyone who powers the machine on reaches the saved browser keys and the Wi-Fi PSK, not just a desktop. That is the same concession the TPM keyslot makes, taken to its conclusion, and it is the right call for a media box. It is not the right call on the laptop, which is exactly why it keeps the passphrase at boot.

### Sunshine

All hosts.

`services.sunshine` starts the daemon with the session and opens the firewall, but the web UI credentials, the TLS certificate and every client pairing live in `~/.config/sunshine/`, which chezmoi does not manage. A reinstall has none of them, and the new certificate invalidates the old pairings anyway.

```sh
systemctl --user status sunshine
```

Open <https://localhost:47990>, accept the self-signed certificate warning, and set the web UI username and password on the first-run screen. Without a browser:

```sh
sunshine --creds <username> <password>
systemctl --user restart sunshine
```

Then pair each client: add the host in Moonlight, and enter the PIN it shows on the web UI's PIN tab. Pairing is per client and per install, so every one has to be redone, including the laptop's own `moonlight-qt` against each HTPC, which is the direction that is easy to forget.

## Per-host configuration files

Four files are owned by `/etc/nixos`. The dotfiles repo only holds a copy:

- `hardware-configuration.nix`
- `hostid.nix`
- `disko.nix`
- `luks-tpm-autounlock.nix`

The `update` alias and the autoupgrade service both copy `/etc/nixos` over the repo copy immediately before every rebuild. **Editing the repo copy by hand does not survive.** The next rebuild overwrites it and commits the overwrite. Change these through `/etc/nixos`, or for the LUKS module through `luks-tpm-autounlock.sh`, which writes both.
