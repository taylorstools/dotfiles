#!/usr/bin/env bash

# Exits 0 while the shell's lock screen is up: hypridle's "if locked" rules.
[[ "$(qs ipc call lock isLocked 2>/dev/null)" == "true" ]]
