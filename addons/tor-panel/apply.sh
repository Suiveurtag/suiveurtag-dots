#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons/tor-panel"

# Upstream dots replace the registry, settings and launcher in quick succession.
sleep "${TOR_PANEL_APPLY_DELAY:-2}"
python3 "$ADDON_DIR/apply.py"
