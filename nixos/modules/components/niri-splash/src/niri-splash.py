"""
niri-splash -- covers the niri session from its first frame until the shell's
surfaces exist, then fades out.

Started before niri (see default.nix): everything slow is loaded while niri is
still coming up, and niri's own cursor is hidden for the duration by pointing
it at a transparent theme through an include it live-reloads.
"""

import argparse
import atexit
import ctypes
import json
import math
import os
import signal
import socket
import stat
import subprocess
import sys
import threading
import time
from pathlib import Path

RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))
UP_FILE = RUNTIME / "niri-splash.up"          # present while the splash is on screen
CURSOR_FILE = Path.home() / ".config/niri/custom/cursor-startup.kdl"
CURSOR_REST = "// niri-splash: no cursor override active\n"
CURSOR_BLANK = ("// niri-splash: written at login, restored when the splash lifts.\n"
                'cursor {\n    xcursor-theme "niri-splash-blank"\n}\n')

DISPLAY_TIMEOUT = 60.0   # no display by then: nothing to cover, exit
READY_TIMEOUT = 20.0     # shell never appeared: uncover anyway
PROBE_GRACE = 5.0        # `niri msg` never answered: uncover anyway
POLL = 0.1

# Spinner geometry, matching plymouth-theme-minimal: a 48x16 box scaled to
# SPIN_W, dots 14 units apart, cycle 18 frames * 4 ticks / 50 per second.
SPIN_W, BOX_W, BOX_H = 74.0, 48.0, 16.0
DOTS, DOT_MIN, DOT_MAX, FADE_MIN, PHASE, PERIOD = 3, 3.2, 5.0, 0.25, 0.7, 1.44


# -- Cursor override ----------------------------------------------------------
# Before anything slow: this is the one thing here that races niri reading
# its config. Normally the file is already blank, written at the previous
# logout by niri-splash-next-boot.service; this covers a first boot or an
# unclean shutdown. Only when no display exists yet -- a splash started into
# a live session must not blank a cursor someone is using.

def _write_cursor(text):
    try:
        if CURSOR_FILE.parent.is_dir():
            CURSOR_FILE.write_text(text)
    except OSError:
        pass


def restore_cursor():
    try:
        if "niri-splash-blank" in CURSOR_FILE.read_text():
            _write_cursor(CURSOR_REST)
    except OSError:
        pass


if not any(RUNTIME.glob("wayland-*")):
    _write_cursor(CURSOR_BLANK)
atexit.register(restore_cursor)


# -- GTK, in the only order that works ----------------------------------------
# GTK 4: gdk_display_open() aborts before gtk_init; gtk_init_check() marks
# GTK initialised on its FIRST call whether or not a display opened, then
# returns TRUE forever; and PyGObject makes that first call at `import Gtk`
# and caches the result. So: preload the library, wait for a display, make
# the one gtk_init_check call ourselves when a socket accepts, fall back to
# gdk_display_open (legal once gtk_init has run), and only then import Gtk.

for _lib in ("libgtk4-layer-shell.so", "libgtk4-layer-shell.so.0"):
    try:
        ctypes.CDLL(_lib, mode=ctypes.RTLD_GLOBAL)
        break
    except OSError:
        pass

import gi  # noqa: E402
gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gdk, GLib  # noqa: E402
import cairo  # noqa: E402

_GTK = None
for _lib in ("libgtk-4.so.1", "libgtk-4.so"):
    try:
        _GTK = ctypes.CDLL(_lib, mode=ctypes.RTLD_GLOBAL)
        break
    except OSError:
        pass


def _gtk_init_check():
    if _GTK is None:
        return False
    fn = _GTK.gtk_init_check
    fn.restype, fn.argtypes = ctypes.c_int, []
    return bool(fn())


def _display_sockets():
    names = []
    env = os.environ.get("WAYLAND_DISPLAY")
    if env:
        names.append(env)
    for p in sorted(RUNTIME.glob("wayland-*")):
        try:
            if (not p.name.endswith(".lock") and p.name not in names
                    and stat.S_ISSOCK(p.stat().st_mode)):
                names.append(p.name)
        except OSError:
            pass
    return names


def _accepts(path):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(0.5)
    try:
        s.connect(str(path))
        return True
    except OSError:
        return False
    finally:
        s.close()


def _niri_socket(display):
    found = list(RUNTIME.glob("niri.*.sock"))
    preferred = [p for p in found if display in p.name] or found
    return max(preferred, key=lambda p: p.stat().st_mtime) if preferred else None


def wait_for_display():
    """(display, waited): waited is False if one was usable at the first look."""
    deadline = time.monotonic() + DISPLAY_TIMEOUT
    inited, waited, next_try = False, False, 0.0
    while time.monotonic() < deadline:
        accepting = False
        for name in _display_sockets():
            if not _accepts(RUNTIME / name):
                continue
            accepting = True
            if time.monotonic() < next_try:
                continue
            next_try = time.monotonic() + 0.1
            os.environ["WAYLAND_DISPLAY"] = name
            if not inited:
                inited = True
                display = Gdk.Display.get_default() if _gtk_init_check() else None
            else:
                display = Gdk.Display.open(name)
            if display is not None:
                sock = _niri_socket(name)
                if sock is not None:
                    os.environ["NIRI_SOCKET"] = str(sock)
                return display, waited
        if not accepting:
            waited = True
        time.sleep(0.05)
    return None, waited


DISPLAY, WAITED = wait_for_display()
if DISPLAY is None:
    sys.exit(0)

from gi.repository import Gtk, Gtk4LayerShell as LayerShell  # noqa: E402

try:
    gi.require_version("GLibUnix", "2.0")
    from gi.repository import GLibUnix  # noqa: E402
    _signal_add = GLibUnix.signal_add
except (ImportError, ValueError):
    _signal_add = GLib.unix_signal_add


# -- Window -------------------------------------------------------------------

class Window(Gtk.Window):
    def __init__(self, app, monitor):
        super().__init__()
        self.app = app
        LayerShell.init_for_window(self)
        LayerShell.set_namespace(self, "niri-splash")
        LayerShell.set_layer(self, LayerShell.Layer.OVERLAY)
        if monitor is not None:
            LayerShell.set_monitor(self, monitor)
        for edge in (LayerShell.Edge.TOP, LayerShell.Edge.BOTTOM,
                     LayerShell.Edge.LEFT, LayerShell.Edge.RIGHT):
            LayerShell.set_anchor(self, edge, True)
        LayerShell.set_keyboard_mode(self, LayerShell.KeyboardMode.NONE)
        LayerShell.set_exclusive_zone(self, -1)
        self.set_decorated(False)

        # Background (and logo) repaint only while fading; the spinner is its
        # own small widget so the animation invalidates a few thousand
        # pixels, not the panel -- the renderer is software.
        self.bg = Gtk.DrawingArea()
        self.bg.set_hexpand(True)
        self.bg.set_vexpand(True)
        self.bg.set_draw_func(self._draw_bg)

        scale = SPIN_W / BOX_W
        pad = int(DOT_MAX * scale) + 4
        self.spinner = Gtk.DrawingArea()
        self.spinner.set_size_request(int(BOX_W * scale) + 2 * pad,
                                      int(BOX_H * scale) + 2 * pad)
        self.spinner.set_halign(Gtk.Align.CENTER)
        self.spinner.set_valign(Gtk.Align.CENTER)
        # Centred within (height - margin), so this puts the spinner's centre
        # (logo_h + gap) / 2 below the screen centre: the slot's centre.
        logo_h = app.layout()["logo_h"]
        if logo_h:
            self.spinner.set_margin_top(int(round(logo_h + app.opts.logo_gap)))
        self.spinner.set_draw_func(
            lambda _a, cr, w, h: app.draw_spinner(cr, w, h))

        overlay = Gtk.Overlay()
        overlay.set_child(self.bg)
        overlay.add_overlay(self.spinner)
        self.set_child(overlay)
        self.connect("map", self._on_map)

    def _on_map(self, _w):
        # Click-through: if this ever fails to leave, the desktop underneath
        # must still be usable.
        surface = self.get_surface()
        if surface is not None:
            surface.set_input_region(cairo.Region())
        self.app.on_mapped()

    def redraw(self, background):
        self.spinner.queue_draw()
        if background:
            self.bg.queue_draw()

    def _draw_bg(self, _a, cr, w, h):
        app = self.app
        r, g, b, a = app.bg
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(r, g, b, a * app.alpha)
        cr.paint()
        cr.set_operator(cairo.OPERATOR_OVER)
        app.draw_logo(cr, w, h)


# -- Splash -------------------------------------------------------------------

class Splash:
    def __init__(self, opts):
        self.opts = opts
        self.bg = parse_colour(opts.background)
        self.fg = parse_colour(opts.foreground)
        self.logo = load_png(opts.logo)
        self.alpha = 1.0
        self.windows = []
        self._t0 = time.monotonic()
        self._fade_start = None
        self._done = False
        self._stop = threading.Event()
        self._loop = GLib.MainLoop()
        self._env = dict(os.environ)

    def run(self):
        display = Gdk.Display.get_default() or DISPLAY
        if not LayerShell.is_supported():
            return 1
        css = Gtk.CssProvider()
        css.load_from_string("window, drawingarea { background-color: transparent; }")
        Gtk.StyleContext.add_provider_for_display(
            display, css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        monitors = display.get_monitors()
        n = monitors.get_n_items() if monitors else 0
        self.windows = [Window(self, monitors.get_item(i)) for i in range(n)] \
            or [Window(self, None)]
        for w in self.windows:
            w.present()

        GLib.timeout_add(16, self._tick)
        for sig in (signal.SIGUSR1, signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            _signal_add(GLib.PRIORITY_HIGH, sig, self._on_signal, None)
        threading.Thread(target=self._probe, daemon=True).start()
        self._loop.run()
        return 0

    def on_mapped(self):
        try:
            UP_FILE.write_text(str(os.getpid()))
        except OSError:
            pass

    def _on_signal(self, _ud):
        self.begin_fade()
        return GLib.SOURCE_CONTINUE

    def begin_fade(self):
        if self._fade_start is None and not self._done:
            self._fade_start = time.monotonic()
            restore_cursor()
        return GLib.SOURCE_REMOVE

    def _finish(self):
        if self._done:
            return
        self._done = True
        try:
            UP_FILE.unlink()
        except OSError:
            pass
        self._stop.set()
        self._loop.quit()

    # -- animation --------------------------------------------------------

    def _tick(self):
        if self._done:
            return GLib.SOURCE_REMOVE
        fading = self._fade_start is not None
        if fading:
            p = min(1.0, (time.monotonic() - self._fade_start)
                    / max(self.opts.fade_ms, 1) * 1000.0)
            self.alpha = 1.0 - p * p * (3.0 - 2.0 * p)   # smoothstep
            if p >= 1.0:
                self.alpha = 0.0
                for w in self.windows:
                    w.redraw(True)
                self._finish()
                return GLib.SOURCE_REMOVE
        for w in self.windows:
            w.redraw(fading)
        return GLib.SOURCE_CONTINUE

    def layout(self):
        """Logo + gap + slot centred as one block; the slot holds the spinner
        here and the passphrase field in Plymouth, so the logo stays put."""
        o = self.opts
        if self.logo is None:
            return {"logo_w": 0.0, "logo_h": 0.0, "group_h": o.slot_height}
        logo_h = o.logo_width * self.logo.get_height() / self.logo.get_width()
        return {"logo_w": o.logo_width, "logo_h": logo_h,
                "group_h": logo_h + o.logo_gap + o.slot_height}

    def draw_logo(self, cr, w, h):
        if self.logo is None:
            return
        lay = self.layout()
        scale = lay["logo_w"] / self.logo.get_width()
        cr.save()
        cr.translate(round((w - lay["logo_w"]) / 2), round((h - lay["group_h"]) / 2))
        cr.scale(scale, scale)
        cr.set_source_surface(self.logo, 0, 0)
        cr.get_source().set_filter(cairo.FILTER_BEST)
        cr.paint_with_alpha(self.alpha)
        cr.restore()

    def draw_spinner(self, cr, w, h):
        if self.alpha <= 0.0:
            return
        scale = SPIN_W / BOX_W
        theta = (time.monotonic() - self._t0) / PERIOD * 2.0 * math.pi
        x0 = w / 2.0 - BOX_W / 2.0 * scale
        cy = h / 2.0
        r, g, b, a = self.fg
        for k in range(DOTS):
            t = 0.5 + 0.5 * math.sin(theta - k * PHASE)
            cr.set_source_rgba(r, g, b, a * (FADE_MIN + (1 - FADE_MIN) * t) * self.alpha)
            cr.arc(x0 + (24.0 - (DOTS - 1) * 7.0 + k * 14.0) * scale, cy,
                   (DOT_MIN + (DOT_MAX - DOT_MIN) * t) * scale, 0, 2 * math.pi)
            cr.fill()

    # -- readiness --------------------------------------------------------

    def _layers(self):
        """Namespaces of niri's mapped layer surfaces, or None if unanswered."""
        try:
            r = subprocess.run([self.opts.niri, "msg", "--json", "layers"],
                               capture_output=True, text=True, timeout=5,
                               env=self._env)
            if r.returncode != 0:
                return None
            return set(namespaces(json.loads(r.stdout)))
        except (OSError, subprocess.SubprocessError, ValueError):
            return None

    def already_up(self):
        seen = self._layers()
        return seen is not None and set(self.opts.namespaces) <= seen

    def _probe(self):
        o = self.opts
        if o.hold_ms > 0:
            self._stop.wait(o.hold_ms / 1000.0)
        else:
            deadline = time.monotonic() + READY_TIMEOUT
            grace = time.monotonic() + PROBE_GRACE
            answered = False
            while not self._stop.is_set() and time.monotonic() < deadline:
                seen = self._layers()
                if seen is not None:
                    answered = True
                    if set(o.namespaces) <= seen:
                        break
                elif not answered and time.monotonic() > grace:
                    break
                self._stop.wait(POLL)
        if not self._stop.is_set():
            GLib.idle_add(self.begin_fade)


# -- Helpers ------------------------------------------------------------------

def parse_colour(text):
    s = text.strip().lstrip("#")
    if len(s) == 3:
        s = "".join(c * 2 for c in s)
    if len(s) == 6:
        s += "ff"
    try:
        return tuple(int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4, 6))
    except ValueError:
        return (0.0, 0.0, 0.0, 1.0)


def load_png(path):
    if not path:
        return None
    try:
        return cairo.ImageSurface.create_from_png(path)
    except (OSError, cairo.Error):
        return None


def namespaces(node):
    if isinstance(node, dict):
        found = [node["namespace"]] if isinstance(node.get("namespace"), str) else []
        return found + [n for v in node.values() for n in namespaces(v)]
    if isinstance(node, list):
        return [n for v in node for n in namespaces(v)]
    return []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--namespace", dest="namespaces", action="append", default=[],
                    help="layer-shell namespace that must exist before the "
                         "splash lifts (repeatable; all must)")
    ap.add_argument("--niri", default="niri")
    ap.add_argument("--fade-ms", type=float, default=500)
    ap.add_argument("--hold-ms", type=float, default=0,
                    help="ignore readiness; show for this long (previews)")
    ap.add_argument("--logo", default="", help="PNG above the spinner")
    ap.add_argument("--logo-width", type=float, default=112)
    ap.add_argument("--logo-gap", type=float, default=60)
    ap.add_argument("--slot-height", type=float, default=42,
                    help="Plymouth's passphrase field height")
    ap.add_argument("--background", default="#000000")
    ap.add_argument("--foreground", default="#e6e6e6")
    opts = ap.parse_args()
    if not opts.namespaces:
        opts.namespaces = ["dms:bar"]

    app = Splash(opts)
    # A display that was there at the first look means a live session, not a
    # login; if the shell is up too, there is nothing to cover.
    if not WAITED and opts.hold_ms <= 0 and app.already_up():
        return 0
    try:
        return app.run()
    finally:
        try:
            UP_FILE.unlink()
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())