#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons/wallpaper-random"

# Upstream updates replace several files in quick succession. Let the copy finish
# before checking and reapplying this isolated addon.
sleep "${WALLPAPER_RANDOM_APPLY_DELAY:-2}"
python3 "$ADDON_DIR/apply.py"
