# Quickshell

Taylor's desktop shell for niri.

## How it's deployed

- **Files**: chezmoi ignores this folder (its name starts with a dot).
  `dot_config/symlink_quickshell.tmpl` links `~/.config/quickshell` here, so
  edits take effect without `chezmoi apply`.
- **Autostart**: `dot_config/systemd/user/quickshell.service`, wanted by
  `graphical-session.target`, runs `qs -p ~/.config/quickshell` when niri
  starts and restarts it if it crashes.
- **Packages**: `nixos/modules/components/quickshell.nix` installs what the
  shell calls (matugen, wl-clipboard, wtype, wlsunset, brightnessctl, fd, fzf,
  libnotify), the Material Symbols font, and `qs` itself
  (`myOptions.quickshell.source`).

## Running it

```sh
./run.sh            # stop the service, run here with errors shown (Ctrl+C), start the service after
./run.sh restart    # restart the service
./run.sh logs       # follow the service's log
./run.sh launcher   # toggle the launcher
./run.sh runner     # toggle the runner (port of ~/scripts/runner.sh)
./run.sh clipboard  # toggle the clipboard history
./run.sh notepad    # toggle the notepad
./run.sh settings   # toggle the settings window
./run.sh stop       # stop a running instance
```

Quickshell reloads on save, so leave it running while you edit. Everything
else goes through `qs ipc call <target> <function>`; `qs ipc show` lists them.

## What's here

| Path | What it is |
| --- | --- |
| `shell.qml` | Entry point: bar, dock and wallpaper per monitor, plus every panel below |
| `Bar/` | Bottom bar: workspaces, running apps, clock, tray, battery, status icons |
| `Dock/Dock.qml` | Dock; pin from the launcher or taskbar right-click |
| `Launcher/Launcher.qml` | App search; IPC `launcher` |
| `Runner/Runner.qml` | Win+R-style runner; IPC `runner` |
| `Switcher/WindowSwitcher.qml` | Mod+Tab window switcher with hint letters and search; IPC `switcher` |
| `Clipboard/` | Clipboard history with search and pins; pastes with wtype; IPC `clipboard` |
| `Notepad/Notepad.qml` | Notepad sliding in from the right, with Open and Save As file choosers; IPC `notepad` |
| `ControlCenter/` | Wi-Fi, Bluetooth, volume, brightness, audio output, power; IPC `controlcenter` |
| `Clock/` | Calendar, notification tray and wallpapers; IPC `clock` |
| `Battery/` | Battery flyout: charge, power mode (power-profiles-daemon), battery health; IPC `battery` |
| `Notifications/` | The notification daemon: pop-ups and the card shared with the tray |
| `Osd/Osd.qml` | Volume, brightness and mic OSD; IPC `osd suppress <ms>`. Toasts for scripts in the same spot: `qs ipc call toast info/warn/error <text>` or `toast icon <name> <text>` |
| `PowerMenu/` | Full-screen power menu (lock, log out, sleep, shut down, reboot, Windows), styled like the wlogout it replaced; IPC `powermenu` |
| `Polkit/PolkitDialog.qml` | Polkit password prompt (pkexec, "unlock" buttons) |
| `Whisrs/WhisrsPill.qml` | whisrs dictation pill; IPC `whisrs started` / `stopped` |
| `Wallpaper/` | Wallpaper per screen and the picker shared by the clock flyout and settings; IPC `wallpaper` |
| `Settings/` | Shell Settings window with a search box, saved to `settings.json`; IPC `settings`; in the launcher via `org.quickshell.desktop` |
| `Theming/` | matugen run for the shell and your apps (see below) |
| `Common/` | Theme (colours, sizes), Settings, shared constants |
| `Services/` | niri, apps, network, audio, brightness, night light, clipboard, notifications, blur |
| `Widgets/` | Shared controls: buttons, sliders, toggles, the panel open/close motion |

## Colours

`Theming/generate.sh` runs whenever the wallpaper or a colour setting changes:

1. the shell's palette → `~/.cache/qstest/colors.json`
2. a 16-colour terminal palette (`term16.py`)
3. app themes from `Theming/templates/`: GTK (`shell-colors.css`), niri
   (`colors.kdl`), Ghostty (`shell-colors`), kitty (`shell-theme.conf`,
   `shell-tabs.conf`), KDE (`ShellMatugen*`) and Zed (`shell-theme.json`)
4. your own templates in `~/.config/matugen/config.toml`
5. kitty and Ghostty are told to reload

`QSTEST_THEME_ROOT=/some/dir` writes step 3 there and skips 4 and 5, for
trying changes without touching your apps.
