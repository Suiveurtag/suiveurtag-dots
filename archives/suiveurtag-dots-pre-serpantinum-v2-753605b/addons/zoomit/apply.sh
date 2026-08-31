#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons/zoomit"

sleep "${ZOOMIT_APPLY_DELAY:-2}"
python3 "$ADDON_DIR/apply.py"
