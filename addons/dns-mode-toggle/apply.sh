#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons/dns-mode-toggle"

sleep "${DNS_MODE_TOGGLE_APPLY_DELAY:-2}"
python3 "$ADDON_DIR/apply.py"
