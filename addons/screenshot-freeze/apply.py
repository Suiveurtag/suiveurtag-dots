#!/usr/bin/env python3

from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import shutil
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path


HOME = Path.home()
XDG_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")).expanduser()
XDG_DATA_HOME = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")).expanduser()
XDG_RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")).expanduser()
HYPR_BASE = Path(os.environ.get("HYPR_CONFIG_DIR", XDG_CONFIG_HOME / "hypr")).expanduser()
QS_DIR = Path(os.environ.get("HYPR_QUICKSHELL_DIR", HYPR_BASE / "scripts/quickshell")).expanduser()
SETTINGS = Path(os.environ.get("HYPR_SETTINGS", HYPR_BASE / "settings.json")).expanduser()
SCREENSHOT_SCRIPT = Path(
    os.environ.get("SCREENSHOT_FREEZE_SCRIPT", HYPR_BASE / "scripts/screenshot.sh")
).expanduser()
SCREENSHOT_OVERLAY = Path(
    os.environ.get("SCREENSHOT_FREEZE_OVERLAY", QS_DIR / "ScreenshotOverlay.qml")
).expanduser()
SETTINGS_POPUP = Path(
    os.environ.get("SCREENSHOT_FREEZE_SETTINGS_POPUP", QS_DIR / "settings/SettingsPopup.qml")
).expanduser()
SHELL_QML = QS_DIR / "Shell.qml"
ADDON_DIR = XDG_DATA_HOME / "quickshell-addons/screenshot-freeze"
CARD_SOURCE = ADDON_DIR / "ScreenshotFreezeCard.qml"
CARD_TARGET = SETTINGS_POPUP.parent / "ScreenshotFreezeCard.qml"
BACKUP_DIR = ADDON_DIR / "backups"
LOCK_FILE = XDG_RUNTIME_DIR / "quickshell-addons-settings.lock"

POPUP_MARKERS = (
    "screenshot-freeze import",
    "screenshot-freeze keyboard-toggle",
    "screenshot-freeze general-toggle",
    "screenshot-freeze search-card",
    "screenshot-freeze card",
)
SCRIPT_BEGIN = "# BEGIN user-addon: screenshot-freeze launch"
SCRIPT_END = "# END user-addon: screenshot-freeze launch"
OVERLAY_MARKERS = (
    "screenshot-freeze state",
    "screenshot-freeze background",
    "screenshot-freeze capture",
)


class PatchError(RuntimeError):
    pass


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent, text=True)
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
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    shutil.copy2(path, BACKUP_DIR / f"{path.name}.{stamp}")


def find_matching_brace(text: str, opening: int) -> int:
    if opening < 0 or text[opening] != "{":
        raise PatchError("invalid QML brace anchor")
    depth = 0
    quote = ""
    escaped = False
    line_comment = False
    block_comment = False
    index = opening
    while index < len(text):
        char = text[index]
        following = text[index + 1] if index + 1 < len(text) else ""
        if line_comment:
            if char == "\n":
                line_comment = False
        elif block_comment:
            if char == "*" and following == "/":
                block_comment = False
                index += 1
        elif quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
        elif char == "/" and following == "/":
            line_comment = True
            index += 1
        elif char == "/" and following == "*":
            block_comment = True
            index += 1
        elif char in ('"', "'"):
            quote = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
        index += 1
    raise PatchError("unbalanced QML braces")


def patch_settings_popup(text: str) -> str:
    present = [name for name in POPUP_MARKERS if f"BEGIN user-addon: {name}" in text]
    if present:
        if len(present) != len(POPUP_MARKERS):
            raise PatchError("partial screenshot freeze Settings patch detected")
        return text

    cards = list(re.finditer(r"(?m)^\s*\{\s*tab:\s*0,\s*boxIndex:\s*(\d+).*?$", text))
    max_match = re.search(r"(?m)^(?P<indent>\s*)if \(tab === 0\) return (?P<index>\d+);\s*$", text)
    if not cards or not max_match:
        raise PatchError("General settings index anchors not found")
    addon_index = max(max(int(item.group(1)) for item in cards), int(max_match.group("index"))) + 1

    imports = list(re.finditer(r"(?m)^import .+$", text))
    if not imports:
        raise PatchError("SettingsPopup import anchor not found")
    import_block = (
        "\n// BEGIN user-addon: screenshot-freeze import\n"
        'import "." as ScreenshotFreeze\n'
        "// END user-addon: screenshot-freeze import"
    )
    text = text[: imports[-1].end()] + import_block + text[imports[-1].end() :]

    max_match = re.search(r"(?m)^(?P<indent>\s*)if \(tab === 0\) return (?P<index>\d+);\s*$", text)
    replacement = f'{max_match.group("indent")}if (tab === 0) return {addon_index};'
    text = text[: max_match.start()] + replacement + text[max_match.end() :]

    weather_anchor = re.search(r"(?m)^(?P<indent>\s*)\} else if \(root\.currentTab === 1\) \{$", text)
    if not weather_anchor:
        raise PatchError("General keyboard activation anchor not found")
    indent = weather_anchor.group("indent")
    keyboard = (
        f"{indent}// BEGIN user-addon: screenshot-freeze keyboard-toggle\n"
        f"{indent} else if (root.highlightedBox === {addon_index}) {{\n"
        f"{indent}    if (generalLoader.item) generalLoader.item.toggleScreenshotFreeze();\n"
        f"{indent}}}\n"
        f"{indent}// END user-addon: screenshot-freeze keyboard-toggle\n"
    )
    text = text[: weather_anchor.start()] + keyboard + text[weather_anchor.start() :]

    function_anchor = re.search(
        r"(?m)^(?P<indent>\s*)function focusWpDirInput\(\) \{ wpDirInput\.forceActiveFocus\(\); \}\s*$",
        text,
    )
    if not function_anchor:
        raise PatchError("General functions anchor not found")
    indent = function_anchor.group("indent")
    function_block = (
        f"\n{indent}// BEGIN user-addon: screenshot-freeze general-toggle\n"
        f"{indent}function toggleScreenshotFreeze() {{ screenshotFreezeCard.toggle(); }}\n"
        f"{indent}// END user-addon: screenshot-freeze general-toggle"
    )
    text = text[: function_anchor.end()] + function_block + text[function_anchor.end() :]

    tab_one_card = re.search(r"(?m)^\s*\{\s*tab:\s*1,\s*boxIndex:", text)
    if not tab_one_card:
        raise PatchError("Settings search-card anchor not found")
    card_indent = re.match(r"\s*", tab_one_card.group(0)).group(0)
    search_block = (
        f"{card_indent}// BEGIN user-addon: screenshot-freeze search-card\n"
        f'{card_indent}{{ tab: 0, boxIndex: {addon_index}, label: "Freeze screen during selection", '
        'desc: "Crop screenshots from a still image", icon: "󰹑", color: "blue" },\n'
        f"{card_indent}// END user-addon: screenshot-freeze search-card\n"
    )
    text = text[: tab_one_card.start()] + search_block + text[tab_one_card.start() :]

    main_column = re.search(r"ColumnLayout\s*\{\s*\n\s*id:\s*settingsMainCol\b", text)
    if not main_column:
        raise PatchError("General settings column not found")
    opening = text.find("{", main_column.start())
    closing = find_matching_brace(text, opening)
    card_block = (
        "\n                    // BEGIN user-addon: screenshot-freeze card\n"
        "                    ScreenshotFreeze.ScreenshotFreezeCard {\n"
        "                        id: screenshotFreezeCard\n"
        "                        uiScale: root.s(1)\n"
        f"                        highlighted: root.highlightedBox === {addon_index}\n"
        "                        accentColor: root.blue\n"
        "                        baseColor: root.base\n"
        "                        textColor: root.text\n"
        "                        subtextColor: root.subtext0\n"
        "                        surface0Color: root.surface0\n"
        "                        surface1Color: root.surface1\n"
        "                        surface2Color: root.surface2\n"
        "                        settingsPath: Config.settingsJsonPath\n"
        f"                        onSelected: root.highlightedBox = {addon_index}\n"
        "                    }\n"
        "                    // END user-addon: screenshot-freeze card\n"
        "                "
    )
    return text[:closing] + card_block + text[closing:]


def patch_screenshot_script(text: str) -> str:
    if SCRIPT_BEGIN in text:
        if SCRIPT_END not in text:
            raise PatchError("partial screenshot shell patch detected")
        return text
    required = re.search(r'REQUIRED_CMDS=\((?P<body>[^\n]*)\)', text)
    if not required:
        raise PatchError("screenshot dependency list not found")
    body = required.group("body")
    if '"jq"' not in body:
        body += ' "jq"'
        text = text[: required.start("body")] + body + text[required.end("body") :]
    launch = 'quickshell -p "$QML_PATH"'
    if text.count(launch) != 1:
        raise PatchError("screenshot overlay launch anchor not found")
    block = f'''{SCRIPT_BEGIN}
FREEZE_SETTINGS="${{HYPR_SETTINGS:-${{XDG_CONFIG_HOME:-$HOME/.config}}/hypr/settings.json}}"
export QS_SCREENSHOT_FREEZE="false"
export QS_SCREENSHOT_FROZEN_IMAGE=""

if jq -e '.freezeScreenshotSelection == true' "$FREEZE_SETTINGS" >/dev/null 2>&1; then
    QS_SCREENSHOT_FROZEN_IMAGE=$(mktemp "$QS_RUN_SCREENSHOT/frozen-screen.XXXXXX.png")
    export QS_SCREENSHOT_FROZEN_IMAGE
    trap 'rm -f "$QS_SCREENSHOT_FROZEN_IMAGE"' EXIT

    CURSOR_X=$(hyprctl cursorpos -j | jq -r '.x')
    CURSOR_Y=$(hyprctl cursorpos -j | jq -r '.y')
    QS_SCREENSHOT_FROZEN_OUTPUT=$(hyprctl monitors -j | jq -r \
        --argjson cursorX "$CURSOR_X" --argjson cursorY "$CURSOR_Y" \
        'first(.[] | select($cursorX >= .x and $cursorX < (.x + (.width / .scale)) and $cursorY >= .y and $cursorY < (.y + (.height / .scale))) | .name) // empty')
    if [[ -z "$QS_SCREENSHOT_FROZEN_OUTPUT" ]]; then
        QS_SCREENSHOT_FROZEN_OUTPUT=$(hyprctl monitors -j | jq -r 'first(.[] | select(.focused) | .name) // empty')
    fi
    export QS_SCREENSHOT_FROZEN_OUTPUT

    if [[ -n "$QS_SCREENSHOT_FROZEN_OUTPUT" ]] && grim -o "$QS_SCREENSHOT_FROZEN_OUTPUT" "$QS_SCREENSHOT_FROZEN_IMAGE"; then
        export QS_SCREENSHOT_FREEZE="true"
    else
        rm -f "$QS_SCREENSHOT_FROZEN_IMAGE"
        export QS_SCREENSHOT_FROZEN_IMAGE=""
    fi
fi

{launch}
{SCRIPT_END}'''
    return text.replace(launch, block)


def patch_overlay(text: str) -> str:
    present = [name for name in OVERLAY_MARKERS if f"BEGIN user-addon: {name}" in text]
    if present:
        if len(present) != len(OVERLAY_MARKERS):
            raise PatchError("partial screenshot overlay patch detected")
        return text

    screen_anchor = "    screen: Quickshell.cursorScreen"
    if text.count(screen_anchor) != 1:
        raise PatchError("screenshot overlay screen anchor not found")
    screen_block = '''    function requestedScreen() {
        const output = Quickshell.env("QS_SCREENSHOT_FROZEN_OUTPUT") || "";
        for (let index = 0; index < Quickshell.screens.length; index++) {
            if (Quickshell.screens[index].name === output) return Quickshell.screens[index];
        }
        return Quickshell.cursorScreen;
    }
    screen: requestedScreen()'''
    text = text.replace(screen_anchor, screen_block)

    edit_anchor = re.search(r'(?m)^(?P<indent>\s*)property bool isEditMode: Quickshell\.env\("QS_SCREENSHOT_EDIT"\) === "true"\s*$', text)
    if not edit_anchor:
        raise PatchError("screenshot overlay state anchor not found")
    indent = edit_anchor.group("indent")
    state = (
        f"\n{indent}// BEGIN user-addon: screenshot-freeze state\n"
        f'{indent}property bool freezeActive: Quickshell.env("QS_SCREENSHOT_FREEZE") === "true"\n'
        f'{indent}property string frozenImagePath: Quickshell.env("QS_SCREENSHOT_FROZEN_IMAGE") || ""\n'
        f"{indent}property bool captureInProgress: false\n"
        f"{indent}// END user-addon: screenshot-freeze state"
    )
    text = text[: edit_anchor.end()] + state + text[edit_anchor.end() :]

    background_anchor = re.search(r"(?m)^\s*property string cachedMode:", text)
    if not background_anchor:
        raise PatchError("screenshot overlay background anchor not found")
    background = '''    // BEGIN user-addon: screenshot-freeze background
    Image {
        id: frozenBackground
        anchors.fill: parent
        source: root.freezeActive ? ("file://" + root.frozenImagePath) : ""
        fillMode: Image.Stretch
        cache: false
        smooth: true
        visible: root.freezeActive && !root.isVideoMode
        z: root.captureInProgress ? 1000 : -1
        onStatusChanged: if (status === Image.Error) root.freezeActive = false
    }
    // END user-addon: screenshot-freeze background

'''
    text = text[: background_anchor.start()] + background + text[background_anchor.start() :]

    old = '''        root.visible = false
        captureTimer.pendingCmd = cmd
        captureTimer.start()'''
    if text.count(old) != 1:
        raise PatchError("screenshot capture execution anchor not found")
    new = '''        // BEGIN user-addon: screenshot-freeze capture
        if (root.freezeActive && !isRecord) root.captureInProgress = true
        else root.visible = false
        // END user-addon: screenshot-freeze capture
        captureTimer.pendingCmd = cmd
        captureTimer.start()'''
    return text.replace(old, new)


def validate_qml(path: Path) -> None:
    result = subprocess.run(["qmllint", str(path)], capture_output=True, text=True)
    if result.returncode:
        raise PatchError((result.stdout + result.stderr).strip())


def validate_bash(path: Path) -> None:
    result = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
    if result.returncode:
        raise PatchError(result.stderr.strip())


def install_card() -> bool:
    if not CARD_SOURCE.is_file():
        raise PatchError(f"addon card not found: {CARD_SOURCE}")
    validate_qml(CARD_SOURCE)
    desired = CARD_SOURCE.read_bytes()
    if CARD_TARGET.is_file() and CARD_TARGET.read_bytes() == desired:
        return False
    CARD_TARGET.parent.mkdir(parents=True, exist_ok=True)
    temporary = CARD_TARGET.with_name(f".{CARD_TARGET.name}.screenshot-freeze")
    shutil.copy2(CARD_SOURCE, temporary)
    os.replace(temporary, CARD_TARGET)
    return True


def patch_file(path: Path, patcher, validator) -> bool:
    if not path.is_file():
        raise PatchError(f"upstream file not found: {path}")
    original = path.read_text(encoding="utf-8")
    patched = patcher(original)
    if patched == original:
        validator(path)
        return False
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent, text=True)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(patched)
        os.chmod(temporary, path.stat().st_mode)
        validator(temporary)
        backup(path)
        os.replace(temporary, path)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise
    return True


def write_enabled(enabled: bool | None) -> bool:
    try:
        data = json.loads(SETTINGS.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PatchError(f"invalid settings.json: {error}") from error
    if not isinstance(data, dict):
        raise PatchError("settings.json root is not an object")
    requested = True if enabled is None else enabled
    if "freezeScreenshotSelection" in data and enabled is None:
        return False
    if data.get("freezeScreenshotSelection") is requested:
        return False
    data["freezeScreenshotSelection"] = requested
    backup(SETTINGS)
    atomic_write(SETTINGS, json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    return True


def reload_quickshell() -> None:
    if not SHELL_QML.is_file() or not shutil.which("qs"):
        return
    subprocess.run(
        ["qs", "-p", str(SHELL_QML), "ipc", "call", "main", "forceReload"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Install and manage frozen screenshot selection")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--enable", action="store_true")
    group.add_argument("--disable", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    for command in ("grim", "jq", "qmllint"):
        if not shutil.which(command):
            raise PatchError(f"missing required command: {command}")
    LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)
    with LOCK_FILE.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        explicit = True if args.enable else False if args.disable else None
        changes = []
        if write_enabled(explicit):
            changes.append("saved option")
        if install_card():
            changes.append("card asset")
        if patch_file(SETTINGS_POPUP, patch_settings_popup, validate_qml):
            changes.append("settings UI")
        if patch_file(SCREENSHOT_SCRIPT, patch_screenshot_script, validate_bash):
            changes.append("screenshot launcher")
        if patch_file(SCREENSHOT_OVERLAY, patch_overlay, validate_qml):
            changes.append("selection overlay")
        if changes:
            reload_quickshell()
            print("screenshot-freeze: updated " + ", ".join(changes))
        else:
            print("screenshot-freeze: addon already installed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"screenshot-freeze: {error}; no further changes applied", file=os.sys.stderr)
        raise SystemExit(1)
