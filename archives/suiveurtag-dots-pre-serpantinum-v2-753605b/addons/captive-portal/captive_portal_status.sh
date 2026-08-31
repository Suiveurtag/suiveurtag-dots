#!/usr/bin/env bash
set -euo pipefail

json_escape() {
    local value="${1-}"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/ }
    value=${value//$'\r'/ }
    value=${value//$'\t'/ }
    printf '%s' "$value"
}

active_wifi_iface() {
    LC_ALL=C nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null \
        | awk -F: '$2=="wifi" && $3=="connected" {print $1; exit}'
}

active_wifi_ssid() {
    LC_ALL=C nmcli -t -f ACTIVE,SSID device wifi 2>/dev/null \
        | awk -F: '$1=="yes" {print $2; exit}'
}

connectivity_state() {
    local state
    state="$(LC_ALL=C nmcli networking connectivity check 2>/dev/null | head -n1 | tr -d '[:space:]')"
    if [[ -z "$state" ]]; then
        state="$(LC_ALL=C nmcli -t -f CONNECTIVITY general 2>/dev/null | head -n1 | tr -d '[:space:]')"
    fi
    case "$state" in
        full|portal|limited|none|unknown) printf '%s' "$state" ;;
        *) printf 'unknown' ;;
    esac
}

probe_portal() {
    local probe_url="${1-}"
    local result final_url http_code

    if [[ -z "$probe_url" ]]; then
        probe_url="http://neverssl.com/"
    fi

    if ! command -v curl >/dev/null 2>&1; then
        printf '%s|%s\n' "$probe_url" ""
        return 0
    fi

    result="$(curl -Ls -o /dev/null -w '%{url_effective}|%{http_code}' --max-time 8 "$probe_url" 2>/dev/null || true)"
    final_url="${result%%|*}"
    http_code="${result#*|}"

    if [[ -z "$final_url" ]]; then
        final_url="$probe_url"
    fi

    printf '%s|%s\n' "$final_url" "$http_code"
}

portal_host_from_url() {
    local url="${1-}"
    printf '%s\n' "$url" | awk -F/ '{print $3}'
}

WIFI_IFACE="$(active_wifi_iface)"
SSID="$(active_wifi_ssid)"
CONNECTIVITY="$(connectivity_state)"
STATE="offline"
URL=""
HOST=""
MESSAGE="No active Wi-Fi connection"

if [[ -n "$WIFI_IFACE" && -n "$SSID" ]]; then
    STATE="$CONNECTIVITY"
    MESSAGE="Connected"

    if [[ "$CONNECTIVITY" == "portal" || "$CONNECTIVITY" == "limited" || "$CONNECTIVITY" == "unknown" ]]; then
        IFS='|' read -r URL HTTP_CODE <<< "$(probe_portal "http://neverssl.com/")"
        HOST="$(portal_host_from_url "$URL")"

        if [[ "$CONNECTIVITY" == "unknown" ]]; then
            if [[ -n "$HOST" && "$HOST" != "neverssl.com" && "$HOST" != "www.neverssl.com" ]]; then
                STATE="portal"
            else
                STATE="unknown"
            fi
        fi

        if [[ "$STATE" == "portal" || "$STATE" == "limited" ]]; then
            MESSAGE="Login required before internet access is available"
            if [[ -z "$URL" ]]; then
                URL="http://neverssl.com/"
            fi
        else
            URL=""
            HOST=""
        fi
    elif command -v curl >/dev/null 2>&1; then
        IFS='|' read -r URL HTTP_CODE <<< "$(probe_portal "http://neverssl.com/")"
        HOST="$(portal_host_from_url "$URL")"
        if [[ -n "$HOST" && "$HOST" != "neverssl.com" && "$HOST" != "www.neverssl.com" ]]; then
            STATE="portal"
            MESSAGE="Login required before internet access is available"
        else
            URL=""
            HOST=""
        fi
    fi
fi

SSID_ESC="$(json_escape "$SSID")"
STATE_ESC="$(json_escape "$STATE")"
URL_ESC="$(json_escape "$URL")"
HOST_ESC="$(json_escape "$HOST")"
MESSAGE_ESC="$(json_escape "$MESSAGE")"

printf '{"state":"%s","ssid":"%s","url":"%s","host":"%s","message":"%s"}\n' \
    "$STATE_ESC" "$SSID_ESC" "$URL_ESC" "$HOST_ESC" "$MESSAGE_ESC"
