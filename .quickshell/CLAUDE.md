# Quickshell config: handoff notes

Taylor's own desktop shell for niri on taylorpc. It started as an experiment
in `.quickshell-test` and replaced the shell he used before; nothing of that
shell is left in the system or the dotfiles.

## How it's deployed

- This folder is `~/.dotfiles/.quickshell`. The leading `.` keeps chezmoi from
  deploying it; `dot_config/symlink_quickshell.tmpl` links
  `~/.config/quickshell` to it, so edits and settings-window changes land in
  git directly. (Moving to chezmoi-managed files is planned for later.)
- It runs as the user unit `dot_config/systemd/user/quickshell.service`
  (`qs -p ~/.config/quickshell`, part of graphical-session.target, restarts on
  failure), enabled by the chezmoi symlink in `graphical-session.target.wants`.
  The unit sets `QT_QPA_PLATFORMTHEME=gtk3` like niri's `environment {}`:
  systemd's environment has NixOS's `qt.platformTheme = "gnome"`, under which
  Qt misses icons in `~/.local/share/icons`, and launched apps inherit it.
  Plain `qs ipc call <target> <fn>` reaches it.
- NixOS: `nixos/modules/components/quickshell.nix` installs `qs`
  (`myOptions.quickshell.source`, "git" on the laptop = Quickshell master,
  wrapped to append gtk3's GSettings schemas to `XDG_DATA_DIRS`: GTK's file
  chooser aborts the whole shell without them) and
  what the shell runs (wtype, wlsunset, matugen, fd, fzf, wl-clipboard,
  brightnessctl, libnotify, hypridle, swaybg, adw-gtk3), the Material Symbols
  font, accounts-daemon (the avatar) and polkit (the shell is the agent).
  power-profiles-daemon is on in `power-management.nix`. The niri-splash is
  off; if turned back on it waits for `qstest:bar` and `qstest:dock`.
- niri binds (`dot_config/niri/custom/binds.kdl`), the scripts in `scripts/`,
  wlr-which-key, whisrs and roland call `qs ipc`. niri's `config.kdl` includes
  `colors.kdl` (written by `Theming/`) and the shell's `niri-blur.kdl`, then
  `custom/*.kdl` (layout, rules, cursor...). The repo tag `pre-quickshell` is
  the last state before the switch.

## Rules

- Commit or push only when Taylor asks. Don't run `nixos-rebuild` or a full
  `chezmoi apply` unless he asks.

## Running and iterating

```sh
./run.sh            # stop the service, run here with errors in the terminal, restart it after
./run.sh restart    # systemctl --user restart quickshell
./run.sh logs       # journalctl --user -fu quickshell
./run.sh launcher   # qs ipc call launcher toggle (also runner, clipboard, notepad, settings)
./run.sh stop       # qs kill
```

- Quickshell hot-reloads on save. QML errors print to the terminal running
  `run.sh`, with file and line. A hot reload doesn't pick up a *new* type
  (a new inline `component`, or a new file in a module folder): it fails
  with "X is not a type" until `./run.sh restart`.
- `FileView` has a `loaded` property as well as a `loaded` signal, so
  `view.loaded.connect()` fails from JS; put `onLoaded` on the FileView.
- Testing tips: `QSTEST_THEME_ROOT=/some/dir` sends the app themes there
  instead of `$HOME` (so a test run doesn't recolour his terminals);
  `QSTEST_COLORS_FILE` points the theme at another palette file.
- Machine: taylorpc (ASUS PX13, niri, one laptop screen at scale 1.875, bar at
  the bottom). `myOptions.quickshell.source = "git"`, so `qs` is Quickshell
  master. Some APIs used here (`BackgroundEffect`, `Region.radius`) only exist
  on recent master, which is why they're set from JS behind feature checks.

## Layout

| Path | Role |
| --- | --- |
| `shell.qml` | `ShellRoot`: `Variants` of `Background`, `Bar` and `Dock` per screen, plus `Launcher`, `Runner`, `WindowSwitcher`, `ClipboardPanel`, `PowerMenu`, `Notepad`, `ControlCenter`, `ClockFlyout`, `BatteryFlyout`, `TrayFlyout`, notification `Popups`, `Osd`, `PolkitDialog`, `WhisrsPill` and `SettingsWindow`; starts `NiriBlur`, `ClipboardHistory` and `NightLight` at startup |
| `Common/Theme.qml` | Singleton: palette, sizes, fonts, `barTextSize`/`barIconSize` |
| `Common/Settings.qml` | Singleton: settings edited from the settings window (power commands), a `FileView` + `JsonAdapter` on `settings.json` in this folder |
| `Common/Popouts.qml` | Singleton: which popouts are open (`controlCenterScreen`, `clockScreen` + `clockTab`, `batteryScreen`, `trayScreen` + `trayX`, `settingsOpen`) so per-screen bars can open them; opening one flyout closes the others, `closeFlyouts()` closes all |
| `Common/Config.qml` | Singleton: fixed settings with no place in the settings window yet |
| `Services/Niri.qml` | Singleton: niri IPC. An event-stream socket keeps `workspaces`/`windows` maps; a request socket sends actions (`FocusWindow`, `CloseWindow`, `FocusWorkspace {reference:{Id}}`, `FocusWorkspaceUp/Down`) |
| `Services/Apps.qml` | Singleton: desktop-entry lookups (`iconFor`, `nameFor`) and launcher search/scoring |
| `Services/NotepadStore.qml` | Singleton: notepad tabs, `notepad-session.json` + `notepad-files/` under `~/.local/state/qstest/notepad` |
| `Services/Network.qml` | Singleton: `nmcli` polling, refreshed by `nmcli monitor`; while `listNetworks` is set it also lists Wi-Fi networks, and does connect/disconnect/radio. A saved network that fails sets `passwordNeeded`, and a new password goes in with `nmcli connection modify … wifi-sec.psk` so the profile keeps its settings. The control center keeps the typed password in `passwordDraft` because the list rebuilds on every NetworkManager change |
| `Services/Wallpaper.qml` | Singleton: wallpaper path (in `Settings`), folder listing, matugen run on change; IPC target `wallpaper` (`set`/`random`/`get`) |
| `Wallpaper/Background.qml` | Per-screen PanelWindow on the Background layer (namespace `qstest:wallpaper`), crossfades on change |
| `Services/Notifications.qml` | Singleton: the `NotificationServer` (tracks everything until dismissed), `popups`, do not disturb (in `Settings`), arrival times; IPC target `notifications`. One daemon owns the D-Bus name |
| `Services/DockApps.qml` | Singleton: dock model (pins from `Settings.dockPins`, then running apps by niri layout order), keyed by desktop entry id; pin/unpin/move, activate (launch, focus, cycle windows) |
| `Services/Brightness.qml` | Singleton: backlight via `brightnessctl`; sysfs sends no change events, so `brightness` is polled every 250 ms (ignored briefly after our own writes); IPC target `brightness` (`increment`/`decrement`) |
| `Services/Audio.qml` | Singleton: default sink/source; IPC target `audio` (`increment`/`decrement`/`mute`/`micmute`) |
| `Services/Power.qml` | Singleton: runs the lock/sleep/restart/shutdown commands from `Settings` with `sh -c`, no confirmation |
| `Widgets/` | `StyledText`, `MaterialIcon` (ligature glyphs), `BarPopup` (PopupWindow anchored above an item), `Tooltip`, `IconButton`, `StyledSlider`, `Toggle`, `SegmentButton` (tab bars) |
| `Bar/` | `Bar.qml` plus one file per widget. `TrayFlyout.qml` is the collapsed tray's icons above the chevron, a flyout like the others (Exclusive focus, closes on outside click, Esc, or another flyout); `TrayIcon.qml` is shared by it and the uncollapsed tray. A click anywhere else on the bar closes any flyout on release (a passive `PointHandler`, so cursors and clicks still reach widgets) |
| `Notepad/Notepad.qml` | Right-edge slide-in PanelWindow (Top layer, OnDemand focus, no exclusive zone) with tabs and autosave; Open/Save As are Qt `FileDialog`s (GTK's file chooser under the gtk3 theme; `rules.kdl` floats them at Mission Center's 1000×650). niri draws the notepad's layer above every window, so it slides away while one is open and comes back (with the keyboard) after; `IpcHandler` target `notepad` |
| `ControlCenter/ControlCenter.qml` | Flyout from the status icons: full-screen-above-the-bar PanelWindow (Exclusive focus for Wi-Fi passwords), user + settings/lock/power, brightness, volume + output picker, Wi-Fi/Bluetooth list (connected rows: Disconnect text button; a network's right-click or the connected row's gear opens `netMenu` with Disconnect / Forget = `Network.forget`); IPC target `controlcenter` |
| `Settings/SettingsWindow.qml` | "Shell Settings": a `FloatingWindow` (a normal niri window) in a `LazyLoader`; own title bar (maximize = `niri msg action maximize-window-to-edges`, close); sidebar search over `searchIndex` (add new settings there); Power page edits the commands, Wallpaper page has the folder, matugen scheme and a thumbnail picker; IPC target `settings`. Launcher entry: `dot_local/share/applications/org.quickshell.desktop` (named after Quickshell's app id so the taskbar/dock show it too), icon Tela's grey gear (`preferences`) |
| `Battery/BatteryFlyout.qml` + `Services/BatteryInfo.qml` | Flyout from the bar's battery: charge, state, time left and watts (UPower), power mode switcher (`PowerProfiles` = power-profiles-daemon, what powerprofilesctl sets; Performance hidden if unsupported), and a small "Battery health N%" line (UPower's health, else sysfs energy_full / energy_full_design). `BatteryInfo` also feeds `Bar/Battery.qml`. IPC target `battery` (`toggle`/`close`/`setMode`/`getMode`) |
| `Clock/ClockFlyout.qml` | Flyout from the clock, tabs at the bottom: Overview (time to the second, six-week calendar), Notifications (tray, DND bell, clear all), Wallpapers (`WallpaperPicker`); IPC target `clock` |
| `Notifications/` | `NotificationCard` (shared by tray and pop-ups; `notify-send -i name` arrives as `image://icon/name` and is treated as the app icon) and `Popups` (Overlay layer, `ScriptModel` so timers survive new arrivals): bottom or top right (`Settings.notificationPosition`, Notifications page), 16px in so cards sit inside niri's 8px window gaps. Cards slide themselves in, and back out (`Notifications.closePopup`) before leaving the list, since the list's own add and remove animations don't run for the first and last card; dismissing or running an action waits for the slide, because it destroys the notification. The window spans the screen's height with an input mask over the cards, and unmaps when empty (mapped but empty, niri blurs all of it); mapping takes about as long as the slide, so a card that arrives with the window waits for its first frame (`frameSwapped`) before sliding in. The slide moves a `Translate`, not `x`: the list sets a new card's `x` to 0 when laying it out, which drew it in place for a frame |
| `Wallpaper/WallpaperPicker.qml` | Thumbnail grid shared by the clock flyout and the settings page |
| `Runner/Runner.qml` | Port of `~/scripts/runner.sh` (Win+R): overlay panel, same keys; ranking by `fzf --filter --scheme path --nth 2` over a per-reload list file in `$XDG_RUNTIME_DIR`; IPC target `runner` |
| `Switcher/WindowSwitcher.qml` | Mod+Tab window switcher, port of `~/scripts/niri_window-switcher.sh` (still in `scripts/`, no longer bound): windows from `Niri.sortedWindows`, workspace gutter, a dot on the window you came from, one hint letter per window (app name first, then title, then any free key; kept per niri session in `$XDG_RUNTIME_DIR/qstest-switcher-letters.<socket>.json`), `/` for in-order fuzzy search, Delete closes, Esc quits. Closes when another real window gets focus (taking the keyboard reports focus on no window, which doesn't count). IPC target `switcher` |
| `Runner/runner-helper.sh` | The script's shell parts kept as-is: `list-dir`, `list-below` (fd), `dir`, `kind` (the xed/VSCodium text check), `run` (Alt+Enter rules) |
| `Osd/Osd.qml` | Bottom-center OSD for volume, brightness and mic mute; reacts to level changes from any source, quiet while the control center is open, for 1 s after startup or a device switch, and while `qs ipc call osd suppress <ms>` says (hypridle's dim/restore scripts). Also toasts: scripts' short messages in the same pill and spot, sized to the text (`Config.toastMaxWidth`), 3 s, never in the notification tray; IPC target `toast` (`info`/`warn`/`error <text>`, `icon <material icon> <text>`), used by the refresh-rate, scale and hypridle-toggle scripts |
| `Dock/Dock.qml` | Per-screen vertical dock (left, 30px icons, 8px spacing, 1px border in the panel border colour, circle indicators, auto-hide via an input `mask` that shrinks to a 2px edge strip, also shown during niri overview); right-click menu via `DockPopup`. Settings page: Dock |
| `Services/ClipboardHistory.qml` + `Clipboard/clip-helper.sh` | Clipboard history: `wl-paste --watch` runs the helper per copy (skips `CLIPBOARD_STATE=sensitive`), files + `index.json` in `~/.local/state/qstest/clipboard`, dedupe by sha1, 100 unpinned / 5 MB. Paste = copy, close, 200 ms, then Ctrl+V (Ctrl+Shift+V for terminals) via `wtype` only; without wtype it only copies. Clear-at-login uses a marker in `$XDG_RUNTIME_DIR` so config reloads don't clear |
| `Clipboard/ClipboardPanel.qml` | Launcher-style panel; IPC targets `clipboard` (panel) and `cliphistory` (`clear`) |
| `Services/NightLight.qml` | Singleton: night light through `wlsunset` (day/night temperatures 1K apart, so it stays put); `Settings.nightLight`/`nightLightTemperature`; IPC target `night` (`toggle`/`enable`/`disable`/`status`/`getTemp`/`setTemp`) |
| `PowerMenu/PowerMenu.qml` | Full-screen power menu that replaced wlogout and copies its look (measured against wlogout screenshots): the effects wallpaper (`~/.config/.EffectsWallpaper.png`, made by `scripts/niri_make-effects-wallpaper.sh`), six buttons each its label's width plus an equal share of the row, wlogout's own white icons in `PowerMenu/icons/` tinted with `MultiEffect` in `Theme.tertiaryLightScheme` (matugen's light-scheme tertiary) and `Theme.tertiary` on hover, growing 60 to 85px with wlogout's overshoot curve. Keys L/E/Z/S/R/W, Esc or a click outside closes. Lock, sleep, reboot and shut down use the Settings commands (`Services/Power.qml`). Ctrl+Alt+Delete, the which-key menu and the Lock/Sleep/Logout/Shutdown/Reboot launcher entries open it; IPC target `powermenu` |
| `Polkit/PolkitDialog.qml` | The polkit authentication agent (`Quickshell.Services.Polkit`); can't register while another agent runs |
| `Whisrs/WhisrsPill.qml` | Port of Taylor's old WhisrsPill plugin; IPC target `whisrs` (`started`/`stopped`, called by whisrs's hooks) |
| `Theming/` | `generate.sh` (run by `Services/Wallpaper.qml`): the shell palette, a 16-colour terminal palette (`term16.py`, imported as `term16`), app templates adapted from DankMaterialShell's (MIT; `templates.toml` + `templates/`) written to `shell-*` names the app configs include, then Taylor's own `~/.config/matugen` templates, then kitty/Ghostty reload |
| `Launcher/Launcher.qml` | Full-screen transparent overlay PanelWindow with a centered panel; `IpcHandler` target `launcher` (`toggle`/`open`/`close`) |

Imports use Quickshell's `qs.<Dir>` module system (`import qs.Common`, etc.).
Singletons are just files with `pragma Singleton`; there are no qmldir files.
Inline `component`s don't reliably see ids of the file around them, so menu
rows emit `clicked` and the code that uses them does the outer work.

## Decisions already made (and why)

- **Windows come from niri IPC, not `ToplevelManager`.** Running apps are
  ordered by layout: output, workspace idx,
  `layout.pos_in_scrolling_layout` column, then row. Activate and close also
  go through niri.
- **Repeaters are keyed by ids.** Their models are plain window ids (or app
  ids when grouped), and each delegate looks up `Niri.windows[id]`. niri sends
  new JSON objects on every change, so keying by object would rebuild every
  delegate (and lose hover state) whenever a title changes.
- **Better Running Apps is a near-literal port of Taylor's old plugin of that
  name** (the original is in git history under `dot_config/dms/plugins/`). It keeps the same width
  math, with one addition: `Bar.qml` passes the bar's real free space in as
  `allottedPrimarySize`. Only the horizontal layout was ported. Its plugin
  settings are `Settings.runningApps*`, on the settings window's Taskbar page.
- **Better Clock is ported from Taylor's old plugin of that name**
  (horizontal only). Its click emits
  `clockClicked`.
- **The palette is read live from `~/.cache/qstest/colors.json`**, which
  `Services/Wallpaper.qml` writes by running `matugen image <wallpaper> --json hex
  --dry-run --source-color-index 0` (the index flag skips matugen's interactive
  prompt). `QSTEST_COLORS_FILE` points `Theme.pick` at another matugen JSON.
  Taylor found a neutral palette bland, so the Wallpaper settings page has
  three colour knobs in `Settings`: `matugenScheme` (incl. vibrant),
  `colorfulSeed` (`--prefer saturation` instead of `--source-color-index 0`,
  more wallust-like). The surface tint lives on the Appearance page:
  `surfaceTint` (0..1) of `Theme.tintColor` (`surfaceTintColor`: matugen
  primary/secondary/tertiary, or `custom` = `surfaceTintCustom` hex, with a
  "Pick" button using `niri msg pick-color`) is blended into `surface*` in
  `Theme.tint()`; `pick()` returns strings, so it goes through `Qt.color()`
  first. The panel border (`Theme.blurBorder`, every panel and flyout and
  the dock, but not the taskbar) is set the same way: `borderColor` (+ outline/text),
  `borderColorCustom`, `borderOpacity`; attached, the control center,
  calendar and notepad only get it with `attachedPanelBorder`
  (`Theme.edgePanelBorder`). Both use `Theme.namedColor()` and
  the settings window's `ColorSetting` component.
- **Fonts are settings** (Appearance): `Settings.fontFamily` + `fontWeight`
  ("regular"/"medium") feed `Theme.fontFamily`/`fontWeight`, which
  `StyledText` and every TextInput/TextEdit use; `monoFontFamily` feeds
  `Theme.monoFamily` (settings-window command/colour fields). Default Inter + medium renders identically to the old
  "Inter Medium" family name (checked pixel for pixel on the bar). The runner uses the
  shell font, not monospace (Taylor's choice). Don't hard-code font names.
- **Animations follow one setting**, `Settings.animationDuration` (ms,
  110 by default, 0 = off) via `Theme.animDuration` / `animShort`. Panels use
  `Widgets/PanelMotion.qml`: bind `shown`, animate with `progress`, and use
  `mapped` as the window's `visible` so it stays up through the close. Centred
  panels fade and grow from 95%, bar flyouts rise 16px, the notepad slides,
  notification pop-ups slide in and out from the screen edge at twice the
  duration (`Notifications.popupSlideDuration`). The wallpaper crossfade has its own `wallpaperFadeDuration`.
- **Opacity and blur are global settings** (Appearance page):
  `Settings.surfaceOpacity` feeds `Theme.barBackground`/`popupBackground`, which
  every panel uses; `Settings.blur` switches the `BackgroundEffect` region on
  every layer-shell window (each re-applies on `onBlurChanged`). Blur
  *strength* is niri's (one `blur {}` block), so `Services/NiriBlur.qml`
  writes `~/.local/state/qstest/niri-blur.kdl` (offset =
  strength / 14) and reports whether config.kdl includes it. niri ignores the
  blur protocol on normal windows: the settings window only blurs through a
  niri window-rule (app-id `org.quickshell`, title `Shell Settings`), which
  NiriBlur writes into the same file only while `Settings.blur` is on, along
  with a `^qstest:` layer rule carrying `xray` (`Settings.blurXray`, default
  on: blur shows only the wallpaper, not windows behind).
  Notification pop-ups share one window, so each card adds a child `Region`
  to the window's blur region.
  Keys map matugen roles (e.g. `surfaceText` = `on_background`). Bar, dock and popups =
  `surface_container` @ the opacity setting (the bar used the darker `surface`
  until Taylor wanted them to match), launcher border = `primary` @ 0.8.
- **Edge panels attach or float** (`Settings.attachPanels`, default on):
  attached, the control center, clock flyout and notepad have no gap;
  floating keeps the gap. The control center and clock flyout use
  `Settings.flyoutRadius` either way: attached, they reach
  `Theme.flyoutOvershoot` (radius + 1) past the window's bottom and right,
  so those corners and borders are off screen and only the top-left corner
  is rounded; their content and menus keep clear of that strip, and the
  blur region is intersected with the window. The attached notepad is
  square with a left border only (`Widgets/PanelEdges.qml`). Each panel
  re-applies its blur region when these change.
- **The bar was matched pixel by pixel to Taylor's previous bar** on taylorpc
  (scale 1.875), by capturing both with grim and comparing column extents.
  Sizes snap to physical pixels: widget 26.67 / bar 37.33 (50 / 70 px), so
  text is 12px and control-center icons 16px; widget padding is 6 ×
  widgetThickness / 30 (5.33); 4px end margins; Text.NativeRendering for text
  and icons. The gaps between right-side widgets and two 1px offsets in
  `Bar.qml` are measured values (commented). The workspace pills: active
  1.05×, inactive 0.7×, height 0.5× widget thickness, spacing 8.
- **The tray is collapsed behind a chevron** (`Config.collapseTray`),
  Windows-style.
- **Icon names and thresholds** (battery ladder, `wifi` /
  `wifi_2_bar` / `wifi_1_bar` / `wifi_off`, the volume rules).

## Verification so far

Checked live on taylorpc with grim screenshots and `qs ipc`. Things that need
a pointer (hover, clicks, drags) are usually Taylor's to check.

## Likely next steps

1. After the switch: check the gaps above, then move `.quickshell` to
   chezmoi-managed files.
2. Launcher extras: usage-based ordering, a `>` command runner.
3. Maybe rename the `qstest` names (state dirs, namespaces, env vars) now
   that it isn't a test.

## Taylor's preferences

- Config files belong in the chezmoi tree, not generated from Nix. He doesn't
  use home-manager.
- Plain comments that explain why. No long `----` banner or divider lines.
- He wants changes he can follow. Explain what changed and why in a sentence
  or two; no long recaps.
