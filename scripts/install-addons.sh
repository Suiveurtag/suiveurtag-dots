#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDONS_SRC="$REPO_DIR/addons"
SYSTEMD_SRC="$REPO_DIR/systemd/user"

ADDONS_DST="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons"
SYSTEMD_DST="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERPANTINUM_HOME_DIR="${SERPANTINUM_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/serpantinum}"
SERPANTINUM_QS_DIR="$SERPANTINUM_HOME_DIR/src/quickshell"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"

warn() {
    echo "warning: $*" >&2
}

info() {
    printf '  • %s\n' "$*"
}

user_systemctl() {
    if [[ -z "${XDG_RUNTIME_DIR:-}" ]] || ! command -v systemctl >/dev/null 2>&1; then
        return 1
    fi
    systemctl --user "$@"
}

install_addon() {
    local name="$1"
    local src="$ADDONS_SRC/$name"
    local dst="$ADDONS_DST/$name"

    if [[ ! -d "$src" ]]; then
        echo "error: addon source not found: $src" >&2
        exit 1
    fi

    mkdir -p "$dst"
    cp -a "$src/." "$dst/"
    [[ -f "$dst/apply.sh" ]] && chmod +x "$dst/apply.sh"
    [[ -f "$dst/apply.py" ]] && chmod +x "$dst/apply.py"
    [[ -f "$dst/zoomit.py" ]] && chmod +x "$dst/zoomit.py"
    [[ -f "$dst/loopback.py" ]] && chmod +x "$dst/loopback.py"
    if [[ "$name" == "tor-panel" ]]; then
        find "$dst" -maxdepth 1 -type f \( -name '*.py' -o -name '*.sh' \) -exec chmod +x {} +
    fi
}

install_monitor_cycle() {
    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"
    install -m 0755 \
        "$ADDONS_SRC/mouse-monitor-cycle/cycle-mouse-monitor" \
        "$bin_dir/cycle-mouse-monitor"
}

install_serpantinum_v2_addons() {
    info "Serpantinum V2 found at $SERPANTINUM_HOME_DIR"

    local addon
    for addon in \
        emoji-picker \
        mouse-monitor-cycle \
        zoomit \
        launcher-web-search \
        drawing-notes \
        custom-alarm-clock \
        wallpaper-random \
        calendar-legacy \
        serpantinum-settings \
        matugen-vibrant \
        screenshot-freeze \
        music-preview-rounded \
        idle-inhibit \
        headset-mic-loopback \
        captive-portal \
        speedtest \
        dns-mode-toggle \
        wifi-hold-sound \
        tor-panel; do
        install_addon "$addon"
    done
    install_monitor_cycle

    cp "$REPO_DIR/scripts/apply-serpantinum-v2.py" "$ADDONS_DST/apply-serpantinum-v2.py"
    chmod +x "$ADDONS_DST/apply-serpantinum-v2.py"

    mkdir -p "$SYSTEMD_DST"
    local unit
    for unit in \
        serpantinum-addons.path \
        serpantinum-addons.service \
        hypr-zoomit.service \
        tor-panel-tor.service; do
        sed \
            -e "s#%h/.local/share/quickshell-addons#$ADDONS_DST#g" \
            -e "s#%h/.local/share/serpantinum#$SERPANTINUM_HOME_DIR#g" \
            -e "s#%h/.local/state/serpantinum#$STATE_DIR/serpantinum#g" \
            "$SYSTEMD_SRC/$unit" > "$SYSTEMD_DST/$unit"
    done

    env \
        XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}" \
        XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}" \
        SERPANTINUM_HOME="$SERPANTINUM_HOME_DIR" \
        "$ADDONS_DST/apply-serpantinum-v2.py"

    if user_systemctl daemon-reload; then
        user_systemctl enable --now serpantinum-addons.path hypr-zoomit.service
    else
        warn "user systemd session unavailable; enable serpantinum-addons.path and hypr-zoomit.service after login"
    fi

    if command -v serpantinum >/dev/null 2>&1; then
        serpantinum reload || warn "Serpantinum reload failed; use Super+R after installation"
    fi

    info "Serpantinum V2 addons installed"
}

required=(
    "$SERPANTINUM_QS_DIR/Shell.qml"
)
missing=()
for path in "${required[@]}"; do
    [[ -f "$path" ]] || missing+=("$path")
done

if ((${#missing[@]} > 0)); then
    echo "error: Serpantinum's base shell was not found." >&2
    echo "  missing path: ${missing[*]}" >&2
    echo "  install Serpantinum separately, then rerun this installer." >&2
    exit 1
fi

install_serpantinum_v2_addons
