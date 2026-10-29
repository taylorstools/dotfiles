# Quickshell test config: handoff notes

This folder is Taylor's experiment in replacing DankMaterialShell (renamed Dux
Shell in 2.0) with a Quickshell config of his own. It was started in a Claude
cloud session that couldn't reach his desktop, so **nothing here has run on
real Quickshell yet**. The first job is to run it and fix whatever breaks.

## Hard rules

- **Only touch files inside `.quickshell-test/`.** Taylor doesn't want any
  change to the rest of the dotfiles, the chezmoi tree (`dot_config/...`), or
  the NixOS config (`nixos/`) while this is an experiment. That includes niri
  binds: suggest a temporary bind, don't add one.
- The folder name starts with `.` on purpose: chezmoi ignores dot-prefixed
  source entries, so `chezmoi apply` doesn't deploy it. Don't rename it, and
  don't add it to `.chezmoiignore`.
- Commit or push only when Taylor asks.

## Running and iterating

```sh
./run.sh            # runs `qs -p <this folder>` in the foreground, next to DMS
./run.sh solo       # systemctl --user stop dms.service, run, start dms on exit
./run.sh launcher   # qs ipc -p <folder> call launcher toggle
./run.sh notepad    # qs ipc -p <folder> call notepad toggle
./run.sh stop       # qs kill -p <folder>
```

- Quickshell hot-reloads on save. QML errors print to the terminal running
  `run.sh`, with file and line.
- `run.sh` exports `QSTEST_ICON_FONT`, the Material Symbols font bundled
  inside the DMS package (found through `readlink -f $(command -v dms)`). DMS
  doesn't install that font system-wide.
- Machine: taylorpc (ASUS PX13, niri, one laptop screen, bar at the bottom).
  `myOptions.quickshell.source = "git"` on that host, so the `qs` on PATH is
  Quickshell master. Some APIs used here (`BackgroundEffect`, `Region.radius`)
  only exist on recent master, which is why they're set from JS behind
  feature checks.

## Layout

| Path | Role |
| --- | --- |
| `shell.qml` | `ShellRoot`: `Variants` of `Bar` per screen, plus `Launcher` and `Notepad` |
| `Common/Theme.qml` | Singleton: palette, sizes, fonts, `barTextSize`/`barIconSize` (same formulas as DMS) |
| `Common/Config.qml` | Singleton: settings carried over from DMS `settings.json` / `plugin_settings.json` |
| `Services/Niri.qml` | Singleton: niri IPC. An event-stream socket keeps `workspaces`/`windows` maps; a request socket sends actions (`FocusWindow`, `CloseWindow`, `FocusWorkspace {reference:{Id}}`, `FocusWorkspaceUp/Down`) |
| `Services/Apps.qml` | Singleton: desktop-entry lookups (`iconFor`, `nameFor`) and launcher search/scoring |
| `Services/NotepadStore.qml` | Singleton: notepad tabs, same JSON/folder layout as DMS's `NotepadStorageService` but under `~/.local/state/qstest/notepad` (DMS's notes are copied there on first start) |
| `Services/Network.qml` | Singleton: `nmcli` polling, refreshed by `nmcli monitor` |
| `Widgets/` | `StyledText`, `MaterialIcon` (ligature glyphs), `BarPopup` (PopupWindow anchored above an item), `Tooltip` |
| `Bar/` | `Bar.qml` plus one file per widget |
| `Notepad/Notepad.qml` | Right-edge slide-in PanelWindow (Top layer, OnDemand focus, no exclusive zone) with tabs, autosave, Save As/Open path field; `IpcHandler` target `notepad` |
| `Launcher/Launcher.qml` | Full-screen transparent overlay PanelWindow with a centered panel; `IpcHandler` target `launcher` (`toggle`/`open`/`close`) |

Imports use Quickshell's `qs.<Dir>` module system (`import qs.Common`, etc.).
Singletons are just files with `pragma Singleton`; there are no qmldir files.

## Decisions already made (and why)

- **Windows come from niri IPC, not `ToplevelManager`.** Running apps are
  ordered like DMS's `NiriService.sortWindowsByLayout`: output, workspace idx,
  `layout.pos_in_scrolling_layout` column, then row. Activate and close also
  go through niri.
- **Repeaters are keyed by ids.** Their models are plain window ids (or app
  ids when grouped), and each delegate looks up `Niri.windows[id]`. niri sends
  new JSON objects on every change, so keying by object would rebuild every
  delegate (and lose hover state) whenever a title changes.
- **Better Running Apps is a near-literal port of the DMS plugin**
  (`../dot_config/dms/plugins/BetterRunningApps/`). It keeps the same width
  math, with one addition: `Bar.qml` passes the bar's real free space in as
  `allottedPrimarySize`. Only the horizontal layout was ported.
- **Better Clock is ported from `../dot_config/dms/plugins/BetterClock/`**
  (horizontal only). Its click used to open the DMS dash; now it only emits
  `clockClicked`.
- **The palette is read live from `~/.cache/dms/dms-colors.json`**, which DMS's
  matugen run writes. Keys map the way DMS's `buildExtractedDynamicMode` maps
  them (e.g. `surfaceText` = `on_background`). Bar = `surface` @ 0.8, popups =
  `surface_container` @ 0.8, launcher border = `primary` @ 0.8.
- **Sizes match what DMS computes for Taylor's bar config** (innerPadding 1,
  spacing 0, noBackground, squareCorners, fixed 12px radius, font "Inter
  Medium"): bar 36px, widget 28px. The workspace pills follow DMS's "pills"
  ratios: active 1.05×, inactive 0.7×, height 0.5× widget thickness, spacing 8.
- **The tray is collapsed behind a chevron** (`Config.collapseTray`), matching
  the `SessionData.qml` patch in `nixos/modules/components/dms.nix`.
- **Icon names and thresholds were copied from DMS** (battery ladder, `wifi` /
  `wifi_2_bar` / `wifi_1_bar` / `wifi_off`, the volume rules).

## Verification so far

Tested only in a sandbox: PySide6 6.12 offscreen, with hand-written stand-ins
for the Quickshell modules and injected niri events. What passed there: the
bar renders like Taylor's DMS screenshot; window sorting, focus changes, closes
and workspace activation; title shrinking, icon-only fallback, grouping with
count badges; the tray popup; launcher filtering. There were no QML warnings.

Never run against the real APIs:
- Niri `Socket` connect/write/flush and the live event stream
- `SystemTrayItem.display()` menus (needs `//@ pragma UseQApplication`, already set)
- `BackgroundEffect` blur
- `PopupWindow` anchoring (`anchor.item`, `anchor.rect`, `Edges.Top` gravity)
- `IconImage` with real icon themes (Tela)
- UPower percentage scale (the code handles both 0-1 and 0-100)
- `Quickshell.Bluetooth`
- `PwObjectTracker`
- The font loader picking up the DMS font

## Reference material

- DMS source at the commit Taylor runs: `github:duxlabs-dev/dux-shell` rev
  `ee6e941459f0b38e1b075757370a6a6d4cc3daba` (see `nixos/flake.lock`, input
  `dms`). Its `dux-qml-common` submodule holds DCommon and the fonts. Useful
  files: `quickshell/Common/Theme.qml`, `quickshell/Modules/DBar/` (bar,
  metrics, workspace switcher), `quickshell/Services/NiriService.qml`.
- Taylor's DMS settings: `../dot_config/dms/settings.json`,
  `../dot_config/dms/plugin_settings.json`.
- Taylor's niri config: `../dot_config/niri/` (binds in `custom/binds.kdl`
  call `dms ipc ...`).

## Likely next steps

1. Run it live and fix the load errors. Then compare against the DMS bar side
   by side (or with `solo`).
2. Notifications (Quickshell `NotificationServer`). Taylor relies heavily on
   DMS toasts from his own scripts, so this is the big one.
3. A dash or calendar popout from the clock, and a control-center popout from
   the status icons (wifi, bluetooth, volume slider).
4. Launcher extras: usage-based ordering, a `>` command runner (he had DMS's
   commandRunner on with no trigger).
5. OSDs for volume and brightness (his binds currently call `dms ipc call
   audio ...`).
6. Later, outside this folder and only when Taylor asks: material-symbols from
   nixpkgs, a matugen template, binds pointing at `qs ipc`, and a NixOS module.

## Taylor's preferences

- Config files belong in the chezmoi tree, not generated from Nix. He doesn't
  use home-manager.
- Plain comments that explain why. No long `----` banner or divider lines.
- He wants changes he can follow. Explain what changed and why in a sentence
  or two; no long recaps.
