#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons/launcher-web-search"

# Dot updates can replace the launcher while several related files are changing.
sleep "${LAUNCHER_WEB_SEARCH_APPLY_DELAY:-2}"
python3 "$ADDON_DIR/apply.py"
