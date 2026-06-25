#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path


HOME = Path.home()
ADDON_DIR = HOME / ".local/share/quickshell-addons/emoji-picker"
QS_DIR = HOME / ".config/hypr/scripts/quickshell"
REGISTRY = QS_DIR / "WindowRegistry.js"
SETTINGS = HOME / ".config/hypr/settings.json"
INSTALL_DIR = QS_DIR / "emoji"
BACKUP_DIR = ADDON_DIR / "backups"

LAYOUT_BLOCK = (
    '        // BEGIN user-addon: emoji-picker layout\n'
    '        "emoji": { w: s(820, scale), h: s(680, scale), '
    'rx: Math.floor((mw/2)-(s(820, scale)/2)), '
    'ry: Math.floor((mh/2)-(s(680, scale)/2)), '
    'comp: "emoji/EmojiPicker.qml" },\n'
    '        // END user-addon: emoji-picker layout\n'
)

KEYBIND = {
    "type": "bind",
    "mods": "$mainMod",
    "key": "J",
    "dispatcher": "exec",
    "command": "~/.config/hypr/scripts/qs_manager.sh toggle emoji",
    "isEditing": False,
}


class PatchError(RuntimeError):
    pass


def patch_registry(text: str) -> str:
    if "BEGIN user-addon: emoji-picker layout" in text:
        return text

    anchor = re.search(r'^\s*"clipboard":\s*\{.*$', text, flags=re.MULTILINE)
    if not anchor:
        raise PatchError("clipboard layout anchor not found")
    return text[: anchor.end()] + "\n" + LAYOUT_BLOCK + text[anchor.end() :]


def patch_settings(data: dict) -> bool:
    keybinds = data.setdefault("keybinds", [])
    if not isinstance(keybinds, list):
        raise PatchError("settings.json keybinds is not a list")

    cleaned = []
    found = False
    changed = False

    for item in keybinds:
        is_emoji_bind = (
            isinstance(item, dict)
            and item.get("command") == KEYBIND["command"]
        )
        if not is_emoji_bind:
            cleaned.append(item)
            continue

        if not found:
            cleaned.append(KEYBIND.copy())
            found = True
            changed = changed or item != KEYBIND
        else:
            changed = True

    if not found:
        cleaned.append(KEYBIND.copy())
        changed = True

    if changed:
        data["keybinds"] = cleaned
    return changed


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent, text=True)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
        if path.exists():
            os.chmod(temporary, path.stat().st_mode)
        os.replace(temporary, path)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def backup(path: Path) -> None:
    if not path.exists():
        return
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    shutil.copy2(path, BACKUP_DIR / f"{path.name}.{timestamp}")


def validate_qml(path: Path) -> None:
    qmllint = shutil.which("qmllint")
    if not qmllint:
        raise PatchError("qmllint is required but was not found")
    result = subprocess.run(
        [qmllint, "-I", str(QS_DIR), str(path)],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise PatchError((result.stdout + result.stderr).strip())


def install_assets() -> bool:
    changed = False
    INSTALL_DIR.mkdir(parents=True, exist_ok=True)
    for name in ("EmojiPicker.qml", "emojis.json"):
        source = ADDON_DIR / name
        target = INSTALL_DIR / name
        if not source.is_file():
            raise PatchError(f"missing addon asset: {source}")
        if target.is_file() and target.read_bytes() == source.read_bytes():
            continue
        shutil.copy2(source, target)
        changed = True
    return changed


def main() -> int:
    if not REGISTRY.is_file() or not SETTINGS.is_file():
        raise PatchError("active Hyprland/Quickshell configuration not found")

    registry_original = REGISTRY.read_text(encoding="utf-8")
    registry_patched = patch_registry(registry_original)

    try:
        settings_data = json.loads(SETTINGS.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PatchError(f"invalid settings.json: {error}") from error
    settings_changed = patch_settings(settings_data)

    validate_qml(ADDON_DIR / "EmojiPicker.qml")
    assets_changed = install_assets()

    if registry_patched != registry_original:
        backup(REGISTRY)
        atomic_write(REGISTRY, registry_patched)

    if settings_changed:
        backup(SETTINGS)
        atomic_write(SETTINGS, json.dumps(settings_data, ensure_ascii=False, indent=2) + "\n")

    status = []
    if registry_patched != registry_original:
        status.append("layout")
    if settings_changed:
        status.append("keybind")
    if assets_changed:
        status.append("assets")
    print("emoji-picker: updated " + ", ".join(status) if status else "emoji-picker: addon already installed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"emoji-picker: {error}; no core file changed", file=sys.stderr)
        raise SystemExit(1)
