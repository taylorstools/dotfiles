#!/usr/bin/env python3
"""Terminal palette for the app templates.

The Ghostty, kitty and Zed templates read a 16-colour ANSI palette as
`term16`. This builds one from matugen's colours and prints it in the shape
those templates read, for `matugen --import-json`.

Black, white and blue come from the scheme (blue is primary). Red, green,
yellow, magenta and cyan keep their meaning with fixed hues, nudged a little
toward primary so they sit with the rest; taken from a neutral scheme's
tertiary/secondary they came out grey.

Usage: term16.py MATUGEN_JSON > term16.json
"""

import colorsys
import json
import sys


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def rgb_to_hex(rgb):
    return "#" + "".join(f"{round(max(0, min(1, c)) * 255):02x}" for c in rgb)


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def hsl(h, s, l):
    return colorsys.hls_to_rgb(h / 360, l, s)


def main():
    colors = json.load(open(sys.argv[1]))["colors"]

    def c(key):
        return hex_to_rgb(colors[key]["dark"]["color"])

    primary = c("primary")
    white = (1, 1, 1)

    def accent(hue, s, l):
        return mix(hsl(hue, s, l), primary, 0.12)

    palette = [
        c("surface"),                     # 0 black
        accent(5, 0.75, 0.68),            # 1 red
        accent(125, 0.45, 0.62),          # 2 green
        accent(48, 0.90, 0.68),           # 3 yellow
        primary,                          # 4 blue
        accent(300, 0.45, 0.72),          # 5 magenta
        accent(185, 0.45, 0.65),          # 6 cyan
        c("on_surface_variant"),          # 7 white
        c("outline"),                     # 8 bright black (comments)
        accent(5, 0.85, 0.78),            # 9
        accent(125, 0.60, 0.76),          # 10
        accent(48, 1.00, 0.80),           # 11
        mix(primary, white, 0.3),         # 12
        accent(300, 0.60, 0.82),          # 13
        accent(185, 0.60, 0.78),          # 14
        c("on_surface"),                  # 15
    ]

    entries = {}
    for i, rgb in enumerate(palette):
        value = {"hex": rgb_to_hex(rgb), "hex_stripped": rgb_to_hex(rgb)[1:]}
        entries[f"color{i}"] = {"default": value, "dark": value, "light": value}

    json.dump({"term16": entries}, sys.stdout)


if __name__ == "__main__":
    main()
