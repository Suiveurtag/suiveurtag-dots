#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons/music-preview-rounded"

sleep "${MUSIC_PREVIEW_ROUNDED_APPLY_DELAY:-2}"
python3 "$ADDON_DIR/apply.py"
