#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons/idle-inhibit"

if [[ "${1:-}" != "--disable" && "${1:-}" != "--enable" ]]; then
    sleep "${IDLE_INHIBIT_APPLY_DELAY:-2}"
fi
python3 "$ADDON_DIR/apply.py" "$@"
