# Quickshell test config

A standalone Quickshell config to try out next to DMS. Nothing in the NixOS
config or the chezmoi tree points at it, and the folder name starts with a dot,
so chezmoi ignores it too. It only runs when you start it.

## Running it

```sh
./run.sh            # bar + launcher next to DMS (Ctrl+C to quit)
./run.sh solo       # stop DMS while it runs, restart DMS when you quit
./run.sh launcher   # toggle the launcher (from a terminal or a temporary bind)
./run.sh notepad    # toggle the notepad
./run.sh stop       # stop a running instance
```

Quickshell reloads on save, so leave it running while you edit.

With DMS still running, both bars reserve space and this one sits just above
the DMS bar. Use `solo` to see it on its own.

## What's here

| Path | What it is |
| --- | --- |
| `shell.qml` | Entry point: one bar per monitor, plus the launcher and notepad |
| `Bar/Bar.qml` | Bottom bar, laid out like your DMS bar |
| `Bar/BetterRunningApps.qml` | Port of your plugin (adaptive width, icon-only fallback, grouping) |
| `Bar/BetterClock.qml` | Port of your plugin |
| `Bar/WorkspaceSwitcher.qml` | DMS-style workspace pills |
| `Bar/SystemTray.qml` | Tray, collapsed behind a chevron like your `dms.nix` patch |
| `Bar/Battery.qml`, `Bar/StatusIcons.qml` | Battery, network, bluetooth, volume |
| `Launcher/Launcher.qml` | Centered app search; IPC target `launcher` |
| `Notepad/Notepad.qml` | Notepad sliding in from the right; IPC target `notepad` |
| `Common/Theme.qml` | Colors (live from DMS's matugen output), sizes, fonts |
| `Common/Config.qml` | Settings that lived in DMS's settings files |
| `Services/` | niri IPC, desktop-entry lookups and search, nmcli |

## Borrowed from DMS for now

- **Colors** come from `~/.cache/dms/dms-colors.json`, the file DMS's matugen
  run writes, so the palette follows your wallpaper. Once DMS is gone you'd
  point matugen at a template of your own.
- **Icons** use the Material Symbols font that ships inside the DMS package.
  `run.sh` finds it. To drop DMS you'd install `material-symbols` from nixpkgs
  instead.
