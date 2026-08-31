#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons/emoji-picker"

# Dot updates replace related files in quick succession.
sleep "${EMOJI_PICKER_APPLY_DELAY:-2}"
python3 "$ADDON_DIR/apply.py"
