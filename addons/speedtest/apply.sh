#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons/speedtest"

# Dot updates can rewrite the popup in multiple passes. Wait briefly so we patch
# the final version instead of a transient file.
sleep "${SPEEDTEST_APPLY_DELAY:-2}"
python3 "$ADDON_DIR/apply.py"
