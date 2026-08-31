#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons/wifi-text-scroll"

sleep "${WIFI_TEXT_SCROLL_APPLY_DELAY:-2}"
python3 "$ADDON_DIR/apply.py"
