#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons/matugen-vibrant"

if [[ "${1:-}" != "--enable" && "${1:-}" != "--disable" ]]; then
    sleep "${MATUGEN_VIBRANT_APPLY_DELAY:-2}"
fi

python3 "$ADDON_DIR/apply.py" "$@"
