#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons/custom-alarm-clock"

# Dot updates may replace Timer.qml while related Quickshell files are still moving.
sleep "${CUSTOM_ALARM_APPLY_DELAY:-2}"
python3 "$ADDON_DIR/apply.py"
