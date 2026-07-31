#!/usr/bin/env bash
set -euo pipefail

readonly MULLVAD_IPV4="194.242.2.2"
readonly MULLVAD_IPV6="2a07:e340::2"
readonly MULLVAD_HOSTNAME="dns.mullvad.net"
readonly MULLVAD_IPV4_DOT="${MULLVAD_IPV4}#${MULLVAD_HOSTNAME}"
readonly MULLVAD_IPV6_DOT="${MULLVAD_IPV6}#${MULLVAD_HOSTNAME}"
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
command -v resolvectl >/dev/null 2>&1 || fail "systemd-resolved (resolvectl) est introuvable"

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
            -g connection.dns-over-tls,ipv4.ignore-auto-dns,ipv4.dns,ipv6.ignore-auto-dns,ipv6.dns \
            connection show uuid "$connection_uuid"
    )
    dns_over_tls="${dns_settings[0]:--1}"
    ignore_ipv4="${dns_settings[1]:-no}"
    dns_ipv4="${dns_settings[2]:-}"
    ignore_ipv6="${dns_settings[3]:-no}"
    dns_ipv6="${dns_settings[4]:-}"
}

detect_mode() {
    if [[ ( "$dns_over_tls" == "yes" || "$dns_over_tls" == "2" ) \
        && "$ignore_ipv4" == "yes" && "$ignore_ipv6" == "yes" \
        && ",$dns_ipv4," == *",$MULLVAD_IPV4_DOT,"* \
        && ",$dns_ipv6," == *",$MULLVAD_IPV6_DOT,"* ]]; then
        printf 'mullvad'
    elif [[ "$ignore_ipv4" == "no" && "$ignore_ipv6" == "no" \
        && -z "$dns_ipv4" && -z "$dns_ipv6" \
        && "$dns_over_tls" != "yes" && "$dns_over_tls" != "2" ]]; then
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
old_dns_over_tls="$dns_over_tls"

case "$old_dns_over_tls" in
    -1) old_dns_over_tls_value="default" ;;
    0) old_dns_over_tls_value="no" ;;
    1) old_dns_over_tls_value="opportunistic" ;;
    2) old_dns_over_tls_value="yes" ;;
    *) old_dns_over_tls_value="$old_dns_over_tls" ;;
esac

restore_previous_settings() {
    nmcli connection modify uuid "$connection_uuid" \
        connection.dns-over-tls "$old_dns_over_tls_value" \
        ipv4.ignore-auto-dns "$old_ignore_ipv4" \
        ipv4.dns "$old_dns_ipv4" \
        ipv6.ignore-auto-dns "$old_ignore_ipv6" \
        ipv6.dns "$old_dns_ipv6" >/dev/null 2>&1 || true
    nmcli device reapply "$wifi_device" >/dev/null 2>&1 || true
}

if [[ "$target_mode" == "mullvad" ]]; then
    nmcli connection modify uuid "$connection_uuid" \
        connection.dns-over-tls yes \
        ipv4.ignore-auto-dns yes \
        ipv4.dns "$MULLVAD_IPV4_DOT" \
        ipv6.ignore-auto-dns yes \
        ipv6.dns "$MULLVAD_IPV6_DOT"
else
    nmcli connection modify uuid "$connection_uuid" \
        connection.dns-over-tls default \
        ipv4.ignore-auto-dns no \
        ipv4.dns "" \
        ipv6.ignore-auto-dns no \
        ipv6.dns ""
fi

if ! nmcli device reapply "$wifi_device" >/dev/null 2>&1 \
    && ! nmcli connection up uuid "$connection_uuid" ifname "$wifi_device" >/dev/null 2>&1; then
    restore_previous_settings
    fail "NetworkManager n'a pas pu appliquer le nouveau DNS" "$connection_name" "$wifi_device"
fi

read_dns_settings
applied_mode="$(detect_mode)"
if [[ "$applied_mode" != "$target_mode" ]]; then
    restore_previous_settings
    fail "Le profil Wi-Fi n'a pas conservé le mode DNS demandé" "$connection_name" "$wifi_device"
fi

if [[ "$target_mode" == "mullvad" ]]; then
    resolution_ok=false
    for _ in 1 2 3; do
        if resolvectl status "$wifi_device" 2>/dev/null | grep -Fq '+DNSOverTLS' \
            && timeout 4s resolvectl query \
                --cache=no \
                --stale-data=no \
                --legend=no \
                example.com >/dev/null 2>&1; then
            resolution_ok=true
            break
        fi
        sleep 0.2
    done
    if [[ "$resolution_ok" != "true" ]]; then
        restore_previous_settings
        fail "Le DNS-over-TLS Mullvad ne répond pas; mode précédent restauré" "$connection_name" "$wifi_device"
    fi
fi

message="$([[ "$target_mode" == "mullvad" ]] \
    && printf 'DNS-over-TLS Mullvad actif sur cette connexion Wi-Fi' \
    || printf 'DNS automatiques DHCP réactivés')"
emit_json "ok" "$applied_mode" "$connection_name" "$wifi_device" "$message"
