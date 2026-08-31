#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
URL="${1-}"

if [[ -z "$URL" ]]; then
    STATUS_JSON="$("$SCRIPT_DIR/captive_portal_status.sh" 2>/dev/null || true)"
    URL="$(printf '%s' "$STATUS_JSON" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')"
fi

if [[ -z "$URL" ]]; then
    URL="http://neverssl.com/"
fi

if command -v xdg-open >/dev/null 2>&1; then
    nohup xdg-open "$URL" >/dev/null 2>&1 &
elif command -v gio >/dev/null 2>&1; then
    nohup gio open "$URL" >/dev/null 2>&1 &
else
    printf '%s\n' "$URL"
fi
