#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDONS_SRC="$REPO_DIR/addons"
SYSTEMD_SRC="$REPO_DIR/systemd/user"

ADDONS_DST="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons"
SYSTEMD_DST="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

install_addon() {
    local name="$1"
    mkdir -p "$ADDONS_DST/$name"
    cp "$ADDONS_SRC/$name"/* "$ADDONS_DST/$name/"
    chmod +x "$ADDONS_DST/$name/apply.sh" "$ADDONS_DST/$name/apply.py"
}

mkdir -p "$SYSTEMD_DST"

install_addon "wallpaper-random"
install_addon "emoji-picker"

cp "$SYSTEMD_SRC"/* "$SYSTEMD_DST"/

systemctl --user daemon-reload
systemctl --user enable --now wallpaper-random-addon.path emoji-picker-addon.path

WALLPAPER_RANDOM_APPLY_DELAY=0 "$ADDONS_DST/wallpaper-random/apply.sh"
EMOJI_PICKER_APPLY_DELAY=0 "$ADDONS_DST/emoji-picker/apply.sh"

hyprctl reload >/dev/null 2>&1 || true

echo "Installed wallpaper-random and emoji-picker addons."
