#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons/music-preview-rounded"

if [[ "${1:-}" != "--enable" && "${1:-}" != "--disable" ]]; then
    sleep "${MUSIC_PREVIEW_ROUNDED_APPLY_DELAY:-2}"
fi
python3 "$ADDON_DIR/apply.py" "$@"
