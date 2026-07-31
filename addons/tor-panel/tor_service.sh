#!/usr/bin/env bash
set -Eeuo pipefail

mode="${1:-run}"
runtime_dir="${RUNTIME_DIRECTORY:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/tor-panel}"
state_dir="${STATE_DIRECTORY:-${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/tor-panel}"
data_dir="$state_dir/tor-data"

mkdir -p "$runtime_dir" "$data_dir"
chmod 700 "$runtime_dir" "$state_dir" "$data_dir"

tor_args=(
    /usr/bin/tor
    --ignore-missing-torrc
    -f /dev/null
    --RunAsDaemon 0
    --ClientOnly 1
    --DataDirectory "$data_dir"
    --SocksPort "unix:$runtime_dir/socks IsolateSOCKSAuth"
    --ControlPort "unix:$runtime_dir/control"
    --CookieAuthentication 1
    --CookieAuthFile "$runtime_dir/control.authcookie"
    --SafeSocks 1
    --TestSocks 1
    --AvoidDiskWrites 1
    --SafeLogging 1
    --DormantCanceledByStartup 1
    --Log "notice stderr"
)

case "$mode" in
    verify)
        exec "${tor_args[@]}" --verify-config
        ;;
    run)
        exec "${tor_args[@]}"
        ;;
    *)
        printf 'usage: %s verify|run\n' "$0" >&2
        exit 2
        ;;
esac
