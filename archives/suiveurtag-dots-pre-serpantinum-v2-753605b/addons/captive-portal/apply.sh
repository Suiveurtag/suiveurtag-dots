#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons/captive-portal"

# Dot updates can rewrite the popup in multiple passes. Wait briefly so we patch
# the final version instead of a transient file.
sleep "${CAPTIVE_PORTAL_APPLY_DELAY:-2}"
python3 "$ADDON_DIR/apply.py"
