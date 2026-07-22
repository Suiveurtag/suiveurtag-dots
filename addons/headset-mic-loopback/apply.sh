#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons/headset-mic-loopback"

sleep "${HEADSET_MIC_LOOPBACK_APPLY_DELAY:-2}"
python3 "$ADDON_DIR/apply.py"
