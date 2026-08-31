#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons/loading-icon"

# Upstream updates can rewrite several QML files in quick succession.
sleep "${LOADING_ICON_APPLY_DELAY:-4}"
python3 "$ADDON_DIR/apply.py"
