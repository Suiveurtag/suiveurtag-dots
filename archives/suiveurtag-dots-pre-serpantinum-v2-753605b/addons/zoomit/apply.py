#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path


HOME = Path.home()
XDG_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")).expanduser()
XDG_DATA_HOME = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")).expanduser()
HYPR_BASE = Path(os.environ.get("HYPR_CONFIG_DIR", XDG_CONFIG_HOME / "hypr")).expanduser()
QS_DIR = Path(
    os.environ.get("HYPR_QUICKSHELL_DIR", HYPR_BASE / "scripts/quickshell")
).expanduser()
SETTINGS = Path(os.environ.get("HYPR_SETTINGS", HYPR_BASE / "settings.json")).expanduser()
KEYBINDS_CONF = HYPR_BASE / "config/keybindings.conf"
SETTINGS_WATCHER = HYPR_BASE / "scripts/settings_watcher.sh"
SHELL_QML = QS_DIR / "Shell.qml"
ADDON_DIR = XDG_DATA_HOME / "quickshell-addons/zoomit"
BACKUP_DIR = ADDON_DIR / "backups"

KEYBINDS = (
    {
        "type": "bind",
        "mods": "$mainMod ALT",
        "key": "Z",
        "dispatcher": "exec",
        "command": "~/.local/share/quickshell-addons/zoomit/zoomit.py zoom-toggle",
        "isEditing": False,
    },
    {
        "type": "bind",
        "mods": "$mainMod ALT",
        "key": "D",
        "dispatcher": "exec",
        "command": "~/.local/share/quickshell-addons/zoomit/zoomit.py draw-toggle",
        "isEditing": False,
    },
)


class PatchError(RuntimeError):
    pass


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent, text=True
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
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


def validate_dependencies() -> None:
    missing = [name for name in ("hyprctl", "grim", "qs", "qmllint") if not shutil.which(name)]
    if missing:
        raise PatchError("missing required commands: " + ", ".join(missing))
    for asset in ("zoomit.py", "DrawOverlay.qml"):
        if not (ADDON_DIR / asset).is_file():
            raise PatchError(f"missing addon asset: {ADDON_DIR / asset}")
    result = subprocess.run(
        ["qmllint", str(ADDON_DIR / "DrawOverlay.qml")],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise PatchError((result.stdout + result.stderr).strip())


def patch_settings(data: dict) -> bool:
    keybinds = data.setdefault("keybinds", [])
    if not isinstance(keybinds, list):
        raise PatchError("settings.json keybinds is not a list")

    commands = {item["command"] for item in KEYBINDS}
    preserved = []
    for default in KEYBINDS:
        existing = next(
            (
                item
                for item in keybinds
                if isinstance(item, dict)
                and item.get("command") == default["command"]
            ),
            None,
        )
        # The command identifies the addon action. Everything else belongs to
        # the user and must survive Settings edits and watcher reapplications.
        preserved.append(dict(existing) if existing is not None else dict(default))

    cleaned = [
        item
        for item in keybinds
        if not (isinstance(item, dict) and item.get("command") in commands)
    ]
    # Keep the addon visible immediately when opening Settings -> Keybinds.
    patched = preserved + cleaned
    if patched == keybinds:
        return False
    data["keybinds"] = patched
    return True


def keybinds_match_conf(data: dict) -> bool:
    if not KEYBINDS_CONF.is_file():
        return False
    lines = set(KEYBINDS_CONF.read_text(encoding="utf-8").splitlines())
    commands = {item["command"] for item in KEYBINDS}
    active = [
        item
        for item in data.get("keybinds", [])
        if isinstance(item, dict) and item.get("command") in commands
    ]
    if len(active) != len(KEYBINDS):
        return False

    expected = set()
    for item in active:
        line = (
            f'{item.get("type", "bind")} = {item.get("mods", "")}, '
            f'{item.get("key", "")}, {item.get("dispatcher", "exec")}'
        )
        if item.get("command"):
            line += f', {item["command"]}'
        expected.add(line)
    return expected.issubset(lines)


def compile_keybinds() -> None:
    if not SETTINGS_WATCHER.is_file():
        raise PatchError(f"settings_watcher not found: {SETTINGS_WATCHER}")
    result = subprocess.run(
        ["bash", str(SETTINGS_WATCHER), "--compile"],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        details = (result.stdout + result.stderr).strip()
        raise PatchError(f"settings_watcher --compile failed:\n{details}")


def reload_quickshell() -> bool:
    if not SHELL_QML.is_file() or not shutil.which("qs"):
        return False
    result = subprocess.run(
        ["qs", "-p", str(SHELL_QML), "ipc", "call", "main", "forceReload"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


def main() -> int:
    if not SETTINGS.is_file():
        raise PatchError(f"settings.json not found: {SETTINGS}")
    validate_dependencies()
    try:
        data = json.loads(SETTINGS.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PatchError(f"invalid settings.json: {error}") from error
    if not isinstance(data, dict):
        raise PatchError("settings.json root is not an object")

    changed = patch_settings(data)
    if changed:
        backup(SETTINGS)
        atomic_write(SETTINGS, json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    compiled = False
    if changed or not keybinds_match_conf(data):
        compile_keybinds()
        compiled = True
    reloaded = reload_quickshell() if changed else False

    if changed:
        suffix = " and refreshed Settings" if reloaded else ""
        print("zoomit: added zoom and draw keybinds" + suffix)
    elif compiled:
        print("zoomit: keybinds compiled")
    else:
        print("zoomit: addon already installed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"zoomit: {error}; no settings changed", file=sys.stderr)
        raise SystemExit(1)
