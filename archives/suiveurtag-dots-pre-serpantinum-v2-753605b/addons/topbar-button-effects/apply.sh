#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons/topbar-button-effects"

if [[ "${1:-}" != "--enable" && "${1:-}" != "--disable" ]]; then
    sleep "${TOPBAR_BUTTON_EFFECTS_APPLY_DELAY:-2}"
fi
python3 "$ADDON_DIR/apply.py" "$@"
