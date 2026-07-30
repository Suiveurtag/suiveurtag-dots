#!/usr/bin/env bash
set -euo pipefail

readonly MULLVAD_IPV4="194.242.2.2"
readonly MULLVAD_IPV6="2a07:e340::2"
readonly ACTION="${1:-status}"
readonly REQUESTED_MODE="${2:-}"
readonly LOCK_PATH="${XDG_RUNTIME_DIR:-/tmp}/quickshell-dns-mode-toggle.lock"

emit_json() {
    local status="$1"
    local mode="$2"
    local connection="$3"
    local device="$4"
    local message="$5"

    jq -cn \
        --arg status "$status" \
        --arg mode "$mode" \
        --arg connection "$connection" \
        --arg device "$device" \
        --arg message "$message" \
        --arg ipv4 "$MULLVAD_IPV4" \
        --arg ipv6 "$MULLVAD_IPV6" \
        '{
            status: $status,
            mode: $mode,
            connection: $connection,
            device: $device,
            message: $message,
            mullvad_ipv4: $ipv4,
            mullvad_ipv6: $ipv6
        }'
}

fail() {
    local message="$1"
    local connection="${2:-}"
    local device="${3:-}"
    emit_json "error" "unavailable" "$connection" "$device" "$message"
    exit 1
}

command -v nmcli >/dev/null 2>&1 || fail "NetworkManager (nmcli) est introuvable"
command -v jq >/dev/null 2>&1 || fail "jq est introuvable"

exec 9>"$LOCK_PATH"
flock 9

wifi_device="$(
    nmcli -t -f DEVICE,TYPE,STATE device status \
        | awk -F: '$2 == "wifi" && $3 == "connected" { print $1; exit }'
)"
[[ -n "$wifi_device" ]] || fail "Aucune connexion Wi-Fi active"

mapfile -t general < <(
    nmcli --escape no -g GENERAL.CONNECTION,GENERAL.CON-UUID device show "$wifi_device"
)
connection_name="${general[0]:-}"
connection_uuid="${general[1]:-}"
[[ -n "$connection_name" && -n "$connection_uuid" ]] \
    || fail "Impossible d'identifier le profil Wi-Fi actif" "$connection_name" "$wifi_device"

read_dns_settings() {
    mapfile -t dns_settings < <(
        nmcli --escape no \
            -g ipv4.ignore-auto-dns,ipv4.dns,ipv6.ignore-auto-dns,ipv6.dns \
            connection show uuid "$connection_uuid"
    )
    ignore_ipv4="${dns_settings[0]:-no}"
    dns_ipv4="${dns_settings[1]:-}"
    ignore_ipv6="${dns_settings[2]:-no}"
    dns_ipv6="${dns_settings[3]:-}"
}

detect_mode() {
    if [[ "$ignore_ipv4" == "yes" && "$ignore_ipv6" == "yes" \
        && ",$dns_ipv4," == *",$MULLVAD_IPV4,"* \
        && ",$dns_ipv6," == *",$MULLVAD_IPV6,"* ]]; then
        printf 'mullvad'
    elif [[ "$ignore_ipv4" == "no" && "$ignore_ipv6" == "no" \
        && -z "$dns_ipv4" && -z "$dns_ipv6" ]]; then
        printf 'home'
    else
        printf 'custom'
    fi
}

read_dns_settings
current_mode="$(detect_mode)"

if [[ "$ACTION" == "status" ]]; then
    emit_json "ok" "$current_mode" "$connection_name" "$wifi_device" ""
    exit 0
fi

if [[ "$ACTION" == "toggle" ]]; then
    target_mode="$([[ "$current_mode" == "mullvad" ]] && printf 'home' || printf 'mullvad')"
elif [[ "$ACTION" == "set" && ( "$REQUESTED_MODE" == "home" || "$REQUESTED_MODE" == "mullvad" ) ]]; then
    target_mode="$REQUESTED_MODE"
else
    fail "Usage : dns_mode_toggle.sh status|toggle|set home|mullvad" "$connection_name" "$wifi_device"
fi

old_ignore_ipv4="$ignore_ipv4"
old_dns_ipv4="$dns_ipv4"
old_ignore_ipv6="$ignore_ipv6"
old_dns_ipv6="$dns_ipv6"

if [[ "$target_mode" == "mullvad" ]]; then
    nmcli connection modify uuid "$connection_uuid" \
        ipv4.ignore-auto-dns yes \
        ipv4.dns "$MULLVAD_IPV4" \
        ipv6.ignore-auto-dns yes \
        ipv6.dns "$MULLVAD_IPV6"
else
    nmcli connection modify uuid "$connection_uuid" \
        ipv4.ignore-auto-dns no \
        ipv4.dns "" \
        ipv6.ignore-auto-dns no \
        ipv6.dns ""
fi

if ! nmcli device reapply "$wifi_device" >/dev/null 2>&1 \
    && ! nmcli connection up uuid "$connection_uuid" ifname "$wifi_device" >/dev/null 2>&1; then
    nmcli connection modify uuid "$connection_uuid" \
        ipv4.ignore-auto-dns "$old_ignore_ipv4" \
        ipv4.dns "$old_dns_ipv4" \
        ipv6.ignore-auto-dns "$old_ignore_ipv6" \
        ipv6.dns "$old_dns_ipv6" >/dev/null 2>&1 || true
    nmcli device reapply "$wifi_device" >/dev/null 2>&1 || true
    fail "NetworkManager n'a pas pu appliquer le nouveau DNS" "$connection_name" "$wifi_device"
fi

read_dns_settings
applied_mode="$(detect_mode)"
if [[ "$applied_mode" != "$target_mode" ]]; then
    fail "Le profil Wi-Fi n'a pas conservé le mode DNS demandé" "$connection_name" "$wifi_device"
fi

message="$([[ "$target_mode" == "mullvad" ]] \
    && printf 'DNS Mullvad appliqués à cette connexion Wi-Fi' \
    || printf 'DNS automatiques DHCP réactivés')"
emit_json "ok" "$applied_mode" "$connection_name" "$wifi_device" "$message"
