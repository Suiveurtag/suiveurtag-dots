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
XDG_CONFIG_HOME = Path(
    os.environ.get("XDG_CONFIG_HOME", HOME / ".config")
).expanduser()
XDG_DATA_HOME = Path(
    os.environ.get("XDG_DATA_HOME", HOME / ".local/share")
).expanduser()
HYPR_BASE = Path(
    os.environ.get("HYPR_CONFIG_DIR", XDG_CONFIG_HOME / "hypr")
).expanduser()
QS_DIR = Path(
    os.environ.get("HYPR_QUICKSHELL_DIR", HYPR_BASE / "scripts/quickshell")
).expanduser()
SETTINGS = Path(os.environ.get("HYPR_SETTINGS", HYPR_BASE / "settings.json")).expanduser()
REGISTRY = QS_DIR / "WindowRegistry.js"
LAUNCHER = Path(
    os.environ.get("TOR_PANEL_APP_LAUNCHER", QS_DIR / "applauncher/appLauncher.qml")
).expanduser()
SHELL_QML = QS_DIR / "Shell.qml"
KEYBINDS_CONF = HYPR_BASE / "config/keybindings.conf"
SETTINGS_WATCHER = HYPR_BASE / "scripts/settings_watcher.sh"

ADDON_DIR = XDG_DATA_HOME / "quickshell-addons/tor-panel"
SOURCE_QML = ADDON_DIR / "TorPanel.qml"
BACKEND = ADDON_DIR / "tor_panelctl.py"
SERVICE_RUNNER = ADDON_DIR / "tor_service.sh"
SANDBOX_ENTRY = ADDON_DIR / "tor_sandbox_entry.sh"
INSTALL_DIR = QS_DIR / "tor"
INSTALLED_QML = INSTALL_DIR / "TorPanel.qml"
BACKUP_DIR = ADDON_DIR / "backups"

LAYOUT_BLOCK = (
    "        // BEGIN user-addon: tor-panel layout\n"
    '        "tor": { w: s(980, scale), h: s(720, scale), '
    "rx: Math.floor((mw/2)-(s(980, scale)/2)), "
    "ry: Math.floor((mh/2)-(s(720, scale)/2)), "
    'comp: "tor/TorPanel.qml" },\n'
    "        // END user-addon: tor-panel layout\n"
)

KEYBIND = {
    "type": "bind",
    "mods": "$mainMod",
    "key": "K",
    "dispatcher": "exec",
    "command": "bash ~/.config/hypr/scripts/qs_manager.sh toggle tor",
    "isEditing": False,
}

LAUNCH_FUNCTION = r'''    function launchApp(execStr) {
        // user-addon: tor-panel launcher routing
        let dataHome = Quickshell.env("XDG_DATA_HOME");
        let managerPath = (dataHome && dataHome.length > 0
            ? dataHome
            : Quickshell.env("HOME") + "/.local/share")
            + "/quickshell-addons/tor-panel/tor_panelctl.py";
        Quickshell.execDetached(["python3", managerPath, "launch", "--exec", execStr]);
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
    }'''


class PatchError(RuntimeError):
    pass


def backup(path: Path) -> None:
    if not path.exists():
        return
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    shutil.copy2(path, BACKUP_DIR / f"{path.name}.{timestamp}")


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


def atomic_copy(source: Path, target: Path) -> bool:
    if target.is_file() and target.read_bytes() == source.read_bytes():
        return False

    target.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{target.name}.", dir=target.parent
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(source.read_bytes())
        os.chmod(temporary, source.stat().st_mode)
        os.replace(temporary, target)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise
    return True


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


def validate_qml_text(target: Path, content: str) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{target.stem}.", suffix=target.suffix, dir=target.parent, text=True
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
        validate_qml(temporary)
    finally:
        temporary.unlink(missing_ok=True)


def validate_python(path: Path) -> None:
    try:
        compile(path.read_text(encoding="utf-8"), str(path), "exec")
    except (OSError, SyntaxError) as error:
        raise PatchError(f"invalid backend {path}: {error}") from error


def validate_shell(path: Path) -> None:
    result = subprocess.run(
        ["bash", "-n", str(path)],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise PatchError((result.stdout + result.stderr).strip())


def validate_sources() -> None:
    missing = [
        path
        for path in (SOURCE_QML, BACKEND, SERVICE_RUNNER, SANDBOX_ENTRY)
        if not path.is_file()
    ]
    if missing:
        raise PatchError("missing addon asset(s): " + ", ".join(map(str, missing)))
    validate_qml(SOURCE_QML)
    validate_python(BACKEND)
    validate_shell(SERVICE_RUNNER)
    validate_shell(SANDBOX_ENTRY)


def patch_registry(text: str) -> str:
    block_pattern = re.compile(
        r"^[ \t]*// BEGIN user-addon: tor-panel layout\n"
        r".*?"
        r"^[ \t]*// END user-addon: tor-panel layout\n?",
        flags=re.DOTALL | re.MULTILINE,
    )
    matches = list(block_pattern.finditer(text))
    if len(matches) > 1:
        raise PatchError("multiple tor-panel layout blocks found")
    if matches:
        match = matches[0]
        return text[: match.start()] + LAYOUT_BLOCK + text[match.end() :]

    if re.search(r'^\s*"tor"\s*:', text, flags=re.MULTILINE):
        raise PatchError('an unmarked "tor" layout already exists')

    anchor = re.search(r'^\s*"clipboard"\s*:\s*\{.*$', text, flags=re.MULTILINE)
    if not anchor:
        raise PatchError("clipboard layout anchor not found")
    return text[: anchor.end()] + "\n" + LAYOUT_BLOCK + text[anchor.end() :]


def find_matching_brace(text: str, opening: int) -> int:
    depth = 0
    quote = ""
    escaped = False
    line_comment = False
    block_comment = False

    for index in range(opening, len(text)):
        character = text[index]
        following = text[index + 1] if index + 1 < len(text) else ""

        if line_comment:
            if character == "\n":
                line_comment = False
            continue
        if block_comment:
            if character == "*" and following == "/":
                block_comment = False
            continue
        if quote:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == quote:
                quote = ""
            continue

        if character == "/" and following == "/":
            line_comment = True
            continue
        if character == "/" and following == "*":
            block_comment = True
            continue
        if character in ('"', "'", "`"):
            quote = character
        elif character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return index

    raise PatchError("unterminated launchApp function")


def patch_launcher(text: str) -> str:
    matches = list(
        re.finditer(r"^[ \t]*function\s+launchApp\s*\([^)]*\)\s*\{", text, re.MULTILINE)
    )
    if len(matches) != 1:
        raise PatchError(f"expected one launchApp function, found {len(matches)}")

    match = matches[0]
    opening = text.find("{", match.start(), match.end())
    closing = find_matching_brace(text, opening)
    patched = text[: match.start()] + LAUNCH_FUNCTION + text[closing + 1 :]

    # The web-search addon owns these blocks. Tor routing must never consume or
    # rewrite them when both path watchers reapply after a dots update.
    for marker in (
        "BEGIN user-addon: launcher-web-search function",
        "BEGIN user-addon: launcher-web-search tab-handler",
    ):
        if marker in text and marker not in patched:
            raise PatchError(f"launcher-web-search block lost while patching: {marker}")
    return patched


def normalized_binding(mods: object, key: object) -> tuple[tuple[str, ...], str]:
    aliases = {
        "$MAINMOD": "SUPER",
        "WIN": "SUPER",
        "LOGO": "SUPER",
        "MOD4": "SUPER",
        "CONTROL": "CTRL",
    }
    raw_mods = re.split(r"[&\s]+", str(mods or "").strip())
    canonical = tuple(
        sorted(aliases.get(value.upper(), value.upper()) for value in raw_mods if value)
    )
    return canonical, str(key or "").strip().upper()


def patch_settings(data: dict) -> bool:
    keybinds = data.setdefault("keybinds", [])
    if not isinstance(keybinds, list):
        raise PatchError("settings.json keybinds is not a list")

    matching_indices = [
        index
        for index, item in enumerate(keybinds)
        if isinstance(item, dict) and item.get("command") == KEYBIND["command"]
    ]
    existing = keybinds[matching_indices[0]] if matching_indices else None

    if existing is None:
        desired = normalized_binding(KEYBIND["mods"], KEYBIND["key"])
        for item in keybinds:
            if not isinstance(item, dict) or not item.get("key"):
                continue
            if normalized_binding(item.get("mods"), item.get("key")) == desired:
                command = item.get("command", "")
                raise PatchError(f"Meta+K is already assigned to: {command or 'another action'}")

    if existing is None:
        keybinds.append(dict(KEYBIND))
        return True

    # Keep the user's customized binding exactly where it already lives. Other
    # addons also preserve their entries in this array; moving ours to the front
    # would make their path watchers reorder settings.json forever.
    if len(matching_indices) == 1:
        return False

    first = matching_indices[0]
    data["keybinds"] = [
        item
        for index, item in enumerate(keybinds)
        if index == first
        or not (
            isinstance(item, dict)
            and item.get("command") == KEYBIND["command"]
        )
    ]
    return True


def keybind_matches_conf(data: dict) -> bool:
    if not KEYBINDS_CONF.is_file():
        return False
    active = next(
        (
            item
            for item in data.get("keybinds", [])
            if isinstance(item, dict) and item.get("command") == KEYBIND["command"]
        ),
        None,
    )
    if active is None:
        return False
    expected = (
        f'{active.get("type", "bind")} = {active.get("mods", "")}, '
        f'{active.get("key", "")}, {active.get("dispatcher", "exec")}'
    )
    if active.get("command"):
        expected += f', {active["command"]}'
    return expected in KEYBINDS_CONF.read_text(encoding="utf-8").splitlines()


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
    for path in (REGISTRY, SETTINGS, LAUNCHER):
        if not path.is_file():
            raise PatchError(f"active Hyprland/Quickshell file not found: {path}")
    validate_sources()

    registry_original = REGISTRY.read_text(encoding="utf-8")
    registry_patched = patch_registry(registry_original)
    launcher_original = LAUNCHER.read_text(encoding="utf-8")
    launcher_patched = patch_launcher(launcher_original)
    validate_qml_text(LAUNCHER, launcher_patched)

    try:
        settings_data = json.loads(SETTINGS.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PatchError(f"invalid settings.json: {error}") from error
    if not isinstance(settings_data, dict):
        raise PatchError("settings.json root is not an object")
    settings_changed = patch_settings(settings_data)

    asset_changed = not (
        INSTALLED_QML.is_file() and INSTALLED_QML.read_bytes() == SOURCE_QML.read_bytes()
    )
    registry_changed = registry_patched != registry_original
    launcher_changed = launcher_patched != launcher_original

    if asset_changed:
        backup(INSTALLED_QML)
        atomic_copy(SOURCE_QML, INSTALLED_QML)
    if registry_changed:
        backup(REGISTRY)
        atomic_write(REGISTRY, registry_patched)
    if launcher_changed:
        backup(LAUNCHER)
        atomic_write(LAUNCHER, launcher_patched)
    if settings_changed:
        backup(SETTINGS)
        atomic_write(SETTINGS, json.dumps(settings_data, ensure_ascii=False, indent=2) + "\n")

    compiled = False
    if settings_changed or not keybind_matches_conf(settings_data):
        compile_keybinds()
        compiled = True

    changed = asset_changed or registry_changed or launcher_changed or settings_changed
    reloaded = reload_quickshell() if changed else False

    status = []
    if asset_changed:
        status.append("panel asset")
    if registry_changed:
        status.append("layout")
    if launcher_changed:
        status.append("launcher routing")
    if settings_changed:
        status.append("keybind")
    elif compiled:
        status.append("keybinds compiled")
    if reloaded:
        status.append("Quickshell reloaded")

    if status:
        print("tor-panel: updated " + ", ".join(status))
    else:
        print("tor-panel: addon already installed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"tor-panel: {error}", file=sys.stderr)
        raise SystemExit(1)
