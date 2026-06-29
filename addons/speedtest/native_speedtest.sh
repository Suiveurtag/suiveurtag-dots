#!/usr/bin/env bash
set -uo pipefail

export LC_ALL=C

ENDPOINT="${SPEEDTEST_ENDPOINT:-https://speed.cloudflare.com}"
DOWNLOAD_CHUNKS="${SPEEDTEST_DOWNLOAD_CHUNKS:-3}"
DOWNLOAD_BYTES_PER_CHUNK="${SPEEDTEST_DOWNLOAD_BYTES_PER_CHUNK:-1000000}"
UPLOAD_CHUNKS="${SPEEDTEST_UPLOAD_CHUNKS:-2}"
UPLOAD_BYTES_PER_CHUNK="${SPEEDTEST_UPLOAD_BYTES_PER_CHUNK:-500000}"
TIMEOUT="${SPEEDTEST_TIMEOUT:-20}"
STATUS_FILE="${1:-${SPEEDTEST_STATUS_FILE:-}}"

json_escape() {
    local value="${1-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/ }"
    value="${value//$'\r'/ }"
    printf '%s' "$value"
}

emit_status() {
    local status="$1" phase="$2" progress="$3" live="$4" down="$5" up="$6" latency="$7" message="$8"
    local summary=""
    if [[ -n "$down" && -n "$up" ]]; then
        summary="Down ${down} Mbps / Up ${up} Mbps"
    fi

    local payload
    payload="$(printf '{"status":"%s","phase":"%s","progress":%s,"live_mbps":"%s","download_mbps":"%s","upload_mbps":"%s","latency_ms":"%s","server":"Cloudflare","summary":"%s","message":"%s"}\n' \
        "$(json_escape "$status")" \
        "$(json_escape "$phase")" \
        "$progress" \
        "$(json_escape "$live")" \
        "$(json_escape "$down")" \
        "$(json_escape "$up")" \
        "$(json_escape "$latency")" \
        "$(json_escape "$summary")" \
        "$(json_escape "$message")")"

    if [[ -n "$STATUS_FILE" ]]; then
        mkdir -p "$(dirname "$STATUS_FILE")" 2>/dev/null || true
        printf '%s' "$payload" > "$STATUS_FILE"
    fi
    printf '%s' "$payload"
}

finish_error() {
    emit_status "error" "error" "1.0" "0" "" "" "" "$1"
    exit 0
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || finish_error "$1 is required"
}

require_cmd curl
require_cmd awk
require_cmd dd

tmp_upload="$(mktemp "${TMPDIR:-/tmp}/native-speedtest.XXXXXX")" || finish_error "cannot create temp file"
trap 'rm -f "$tmp_upload"' EXIT

emit_status "running" "latency" "0.04" "0" "" "" "" "Testing latency" >/dev/null

latency="$(
    curl -L -sS -o /dev/null \
        --connect-timeout 5 \
        --max-time 8 \
        -w '%{time_starttransfer}' \
        "$ENDPOINT/cdn-cgi/trace" 2>/dev/null \
    | awk '{ printf "%.0f", $1 * 1000 }'
)"

download_total_bytes=0
download_total_time=0
download_mbps=""

for ((i = 1; i <= DOWNLOAD_CHUNKS; i++)); do
    progress="$(awk -v i="$i" -v total="$DOWNLOAD_CHUNKS" 'BEGIN { printf "%.2f", 0.06 + (i - 1) / total * 0.48 }')"
    emit_status "running" "download" "$progress" "${download_mbps:-0}" "$download_mbps" "" "$latency" "Downloading sample $i/$DOWNLOAD_CHUNKS" >/dev/null

    chunk_time="$(
        curl -L -sS -o /dev/null \
            --connect-timeout 8 \
            --max-time "$TIMEOUT" \
            -w '%{time_total}' \
            "$ENDPOINT/__down?bytes=$DOWNLOAD_BYTES_PER_CHUNK" 2>/dev/null
    )" || chunk_time=""

    if [[ -z "$chunk_time" || "$chunk_time" == "0.000000" ]]; then
        finish_error "download test failed"
    fi

    download_total_bytes=$((download_total_bytes + DOWNLOAD_BYTES_PER_CHUNK))
    download_total_time="$(awk -v a="$download_total_time" -v b="$chunk_time" 'BEGIN { printf "%.6f", a + b }')"
    download_mbps="$(awk -v bytes="$download_total_bytes" -v secs="$download_total_time" 'BEGIN { if (secs <= 0) print "0"; else printf "%.1f", (bytes * 8) / secs / 1000000 }')"
    progress="$(awk -v i="$i" -v total="$DOWNLOAD_CHUNKS" 'BEGIN { printf "%.2f", 0.06 + i / total * 0.48 }')"
    emit_status "running" "download" "$progress" "$download_mbps" "$download_mbps" "" "$latency" "Download ${download_mbps} Mbps" >/dev/null
done

dd if=/dev/zero of="$tmp_upload" bs=1M count=$(( (UPLOAD_BYTES_PER_CHUNK + 1048575) / 1048576 )) status=none 2>/dev/null \
    || finish_error "cannot prepare upload payload"
truncate -s "$UPLOAD_BYTES_PER_CHUNK" "$tmp_upload" 2>/dev/null || true

upload_total_bytes=0
upload_total_time=0
upload_mbps=""

for ((i = 1; i <= UPLOAD_CHUNKS; i++)); do
    progress="$(awk -v i="$i" -v total="$UPLOAD_CHUNKS" 'BEGIN { printf "%.2f", 0.56 + (i - 1) / total * 0.40 }')"
    emit_status "running" "upload" "$progress" "${upload_mbps:-0}" "$download_mbps" "$upload_mbps" "$latency" "Uploading sample $i/$UPLOAD_CHUNKS" >/dev/null

    chunk_time="$(
        curl -L -sS -o /dev/null \
            --connect-timeout 8 \
            --max-time "$TIMEOUT" \
            -w '%{time_total}' \
            -X POST \
            --data-binary "@$tmp_upload" \
            "$ENDPOINT/__up" 2>/dev/null
    )" || chunk_time=""

    if [[ -z "$chunk_time" || "$chunk_time" == "0.000000" ]]; then
        emit_status "error" "error" "1.0" "0" "$download_mbps" "" "$latency" "upload test failed"
        exit 0
    fi

    upload_total_bytes=$((upload_total_bytes + UPLOAD_BYTES_PER_CHUNK))
    upload_total_time="$(awk -v a="$upload_total_time" -v b="$chunk_time" 'BEGIN { printf "%.6f", a + b }')"
    upload_mbps="$(awk -v bytes="$upload_total_bytes" -v secs="$upload_total_time" 'BEGIN { if (secs <= 0) print "0"; else printf "%.1f", (bytes * 8) / secs / 1000000 }')"
    progress="$(awk -v i="$i" -v total="$UPLOAD_CHUNKS" 'BEGIN { printf "%.2f", 0.56 + i / total * 0.40 }')"
    emit_status "running" "upload" "$progress" "$upload_mbps" "$download_mbps" "$upload_mbps" "$latency" "Upload ${upload_mbps} Mbps" >/dev/null
done

emit_status "ok" "complete" "1.0" "$download_mbps" "$download_mbps" "$upload_mbps" "${latency:-0}" "Complete"
