"""
dim-overlay.py — Wayland layer-shell screen dimmer (KDE Plasma 6).
"""
import os
import sys
import signal
import json
import argparse
from pathlib import Path

import ctypes  # noqa: E402
try:
    ctypes.CDLL("libgtk4-layer-shell.so", mode=ctypes.RTLD_GLOBAL)
except OSError:
    ctypes.CDLL("libgtk4-layer-shell.so.0", mode=ctypes.RTLD_GLOBAL)

import gi  # noqa: E402
gi.require_version("Gtk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gtk, Gtk4LayerShell as LayerShell, Gdk, GLib  # noqa: E402
import cairo  # noqa: E402


APP_ID       = "dim-overlay"
RUNTIME_DIR  = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))
PID_FILE     = RUNTIME_DIR / "dim-overlay.pid"
STATE_DIR    = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "dim-overlay"
STATE_FILE   = STATE_DIR / "state.json"
OPACITY_STEP = 0.10
OPACITY_MIN  = 0.10
OPACITY_MAX  = 0.99
OPACITY_DEF  = 0.50


# ── State ────────────────────────────────────────────────────────────────────

def load_state(default: float) -> float:
    try:
        with open(STATE_FILE) as f:
            return float(json.load(f).get("opacity", default))
    except (FileNotFoundError, json.JSONDecodeError, ValueError, OSError):
        return default


def save_state(opacity: float) -> None:
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        with open(STATE_FILE, "w") as f:
            json.dump({"opacity": opacity}, f)
    except OSError:
        pass


def write_pid_file() -> None:
    try:
        PID_FILE.write_text(str(os.getpid()))
    except OSError:
        pass


def remove_pid_file() -> None:
    try:
        PID_FILE.unlink()
    except OSError:
        pass


# ── Overlay ──────────────────────────────────────────────────────────────────

class DimOverlay(Gtk.ApplicationWindow):
    def __init__(self, app, monitor, opacity: float):
        super().__init__(application=app)
        self._opacity = self._clamp(opacity)

        LayerShell.init_for_window(self)
        LayerShell.set_namespace(self, APP_ID)
        LayerShell.set_layer(self, LayerShell.Layer.TOP)
        if monitor is not None:
            LayerShell.set_monitor(self, monitor)
        for edge in (LayerShell.Edge.TOP, LayerShell.Edge.BOTTOM,
                     LayerShell.Edge.LEFT, LayerShell.Edge.RIGHT):
            LayerShell.set_anchor(self, edge, True)
        LayerShell.set_keyboard_mode(self, LayerShell.KeyboardMode.NONE)
        LayerShell.set_exclusive_zone(self, -1)

        self.set_decorated(False)

        self._area = Gtk.DrawingArea()
        self._area.set_hexpand(True)
        self._area.set_vexpand(True)
        self._area.set_draw_func(self._draw)
        self.set_child(self._area)

        self.connect("map", self._on_map)

    @staticmethod
    def _clamp(v: float) -> float:
        return max(OPACITY_MIN, min(v, OPACITY_MAX))

    def _on_map(self, _widget):
        surface = self.get_surface()
        if surface is not None:
            surface.set_input_region(cairo.Region())

    def _draw(self, _area, cr, _w, _h):
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0.0, 0.0, 0.0, self._opacity)
        cr.paint()

    def set_dim(self, opacity: float):
        self._opacity = self._clamp(opacity)
        self._area.queue_draw()

    def darker(self):   self.set_dim(self._opacity + OPACITY_STEP)
    def brighter(self): self.set_dim(self._opacity - OPACITY_STEP)


# ── Application ──────────────────────────────────────────────────────────────

class DimApp(Gtk.Application):
    def __init__(self, initial: float):
        super().__init__(application_id="org.user.DimOverlay", flags=0)
        self.initial  = initial
        self.overlays = []

    def do_activate(self):
        display = Gdk.Display.get_default()
        backend = type(display).__name__ if display else "None"
        print(f"dim-overlay: GTK display backend = {backend}", flush=True)

        if not LayerShell.is_supported():
            print("dim-overlay: wlr-layer-shell not advertised by compositor.",
                  file=sys.stderr)
            self.quit()
            return

        css = Gtk.CssProvider()
        css_text = "window, drawingarea { background-color: transparent; }"
        try:
            css.load_from_string(css_text)
        except (AttributeError, TypeError):
            css.load_from_data(css_text.encode())
        Gtk.StyleContext.add_provider_for_display(
            display, css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        monitors = display.get_monitors()
        n = monitors.get_n_items() if monitors else 0

        if n == 0:
            o = DimOverlay(self, None, self.initial); o.present()
            self.overlays.append(o)
        else:
            for i in range(n):
                o = DimOverlay(self, monitors.get_item(i), self.initial)
                o.present()
                self.overlays.append(o)

        self.hold()

        # POSIX signals → main loop.  GLib.unix_signal_add gives proper
        # async-safe signal delivery on the GTK thread.
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGUSR1,
                             self._on_sig_darker, None)
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGUSR2,
                             self._on_sig_brighter, None)
        GLib.unix_signal_add(GLib.PRIORITY_HIGH, signal.SIGTERM,
                             self._on_sig_quit, None)
        GLib.unix_signal_add(GLib.PRIORITY_HIGH, signal.SIGINT,
                             self._on_sig_quit, None)
        GLib.unix_signal_add(GLib.PRIORITY_HIGH, signal.SIGHUP,
                             self._on_sig_quit, None)

    def _on_sig_darker(self, _ud):
        for o in self.overlays: o.darker()
        return GLib.SOURCE_CONTINUE

    def _on_sig_brighter(self, _ud):
        for o in self.overlays: o.brighter()
        return GLib.SOURCE_CONTINUE

    def _on_sig_quit(self, _ud):
        # release() undoes hold() so the main loop can exit, then quit()
        # tears down gracefully.  Return SOURCE_REMOVE so we don't get
        # called twice if another signal arrives mid-shutdown.
        self.release()
        self.quit()
        return GLib.SOURCE_REMOVE


# ── Entry point ──────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--opacity", type=float, default=None,
                    help="Initial dim (0.05–0.95). Default: last saved or 0.4.")
    args = ap.parse_args()

    initial = args.opacity if args.opacity is not None else OPACITY_DEF
    print(f"dim-overlay pid={os.getpid()} opacity={initial:.2f}", flush=True)

    write_pid_file()
    try:
        rc = DimApp(initial).run([])
    finally:
        remove_pid_file()
    sys.exit(rc)


if __name__ == "__main__":
    main()