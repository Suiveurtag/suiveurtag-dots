#!/usr/bin/env bash
set -Eeuo pipefail

readonly SOCKS_SOCKET="${TOR_PANEL_SOCKS_SOCKET:?TOR_PANEL_SOCKS_SOCKET is required}"
readonly LOCAL_SOCKS_PORT="${TOR_PANEL_LOCAL_SOCKS_PORT:-19050}"

if (($# == 0)); then
    echo "tor-panel: no application command supplied" >&2
    exit 2
fi

proxy_pid=""
app_pid=""
proxy_config=""

cleanup() {
    if [[ -n "$app_pid" ]]; then
        kill "$app_pid" 2>/dev/null || true
    fi
    if [[ -n "$proxy_pid" ]]; then
        kill "$proxy_pid" 2>/dev/null || true
        wait "$proxy_pid" 2>/dev/null || true
    fi
    if [[ -n "$proxy_config" ]]; then
        rm -f -- "$proxy_config"
    fi
}
trap cleanup EXIT INT TERM HUP

socat \
    "TCP4-LISTEN:${LOCAL_SOCKS_PORT},bind=127.0.0.1,reuseaddr,fork" \
    "UNIX-CONNECT:${SOCKS_SOCKET}" &
proxy_pid=$!

# Wait for the listener without opening a bogus connection to Tor (which would
# be logged as a malformed SOCKS request).
port_hex="$(printf '%04X' "$LOCAL_SOCKS_PORT")"
listener_ready=false
for _ in {1..40}; do
    kill -0 "$proxy_pid" 2>/dev/null || {
        echo "tor-panel: local SOCKS bridge failed" >&2
        exit 1
    }
    if awk -v needle=":${port_hex}" '$2 ~ needle && $4 == "0A" { found=1 } END { exit !found }' /proc/net/tcp; then
        listener_ready=true
        break
    fi
    sleep 0.05
done
if [[ "$listener_ready" != true ]]; then
    echo "tor-panel: local SOCKS bridge timed out" >&2
    exit 1
fi

proxy_config="$(mktemp)"
isolation_token="torpanel-${TOR_PANEL_ROUTE_ID:-app}-$$-$(date +%s%N)"
isolation_token="${isolation_token//[^a-zA-Z0-9_-]/_}"
isolation_token="${isolation_token:0:120}"
cat > "$proxy_config" <<EOF
strict_chain
proxy_dns
remote_dns_subnet 224
tcp_read_time_out 15000
tcp_connect_time_out 8000
quiet_mode

[ProxyList]
socks5 127.0.0.1 ${LOCAL_SOCKS_PORT} ${isolation_token} route
EOF

proxychains4 -q -f "$proxy_config" "$@" &
app_pid=$!
set +e
wait "$app_pid"
status=$?
set -e
app_pid=""
rm -f -- "$proxy_config"
proxy_config=""
exit "$status"
