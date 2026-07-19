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
XDG_RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
HYPR_BASE = Path(os.environ.get("HYPR_CONFIG_DIR", XDG_CONFIG_HOME / "hypr")).expanduser()
QS_DIR = Path(os.environ.get("HYPR_QUICKSHELL_DIR", HYPR_BASE / "scripts/quickshell")).expanduser()
TOPBAR = Path(os.environ.get("MUSIC_PREVIEW_TOPBAR", QS_DIR / "TopBar.qml")).expanduser()
SETTINGS_POPUP = Path(
    os.environ.get("MUSIC_VISUALIZER_SETTINGS_POPUP", QS_DIR / "settings/SettingsPopup.qml")
).expanduser()
SETTINGS = Path(os.environ.get("HYPR_SETTINGS", HYPR_BASE / "settings.json")).expanduser()
SHELL_QML = QS_DIR / "Shell.qml"
ADDON_DIR = XDG_DATA_HOME / "quickshell-addons/music-preview-rounded"
BACKUP_DIR = ADDON_DIR / "backups"
LOCK_FILE = XDG_RUNTIME_DIR / "quickshell-addons-settings.lock"

ASSETS = {
    ADDON_DIR / "MusicVisualizer.qml": QS_DIR / "MusicVisualizer.qml",
    ADDON_DIR / "MusicVisualizerData.qml": QS_DIR / "MusicVisualizerData.qml",
    ADDON_DIR / "MusicVisualizerCard.qml": SETTINGS_POPUP.parent / "MusicVisualizerCard.qml",
    ADDON_DIR / "AddonSettingsPage.qml": SETTINGS_POPUP.parent / "AddonSettingsPage.qml",
}

IMPORT_BEGIN = "// BEGIN user-addon: music-preview-rounded import"
IMPORT_END = "// END user-addon: music-preview-rounded import"
ART_BEGIN = "// BEGIN user-addon: music-preview-rounded art"
ART_END = "// END user-addon: music-preview-rounded art"
VISUALIZER_BEGIN = "// BEGIN user-addon: music-visualizer controls"
VISUALIZER_END = "// END user-addon: music-visualizer controls"
POPUP_MARKERS = (
    "music-visualizer import",
    "music-visualizer keyboard-toggle",
    "music-visualizer general-toggle",
    "music-visualizer search-card",
    "music-visualizer card",
)
ADDON_CATEGORY_BEGIN = "// BEGIN user-addon: addon-settings category"
ADDON_CATEGORY_END = "// END user-addon: addon-settings category"


class PatchError(RuntimeError):
    pass


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


def patch_rounded_art(text: str) -> str:
    has_import = IMPORT_BEGIN in text and IMPORT_END in text
    has_art = ART_BEGIN in text and ART_END in text
    if has_import != has_art:
        raise PatchError("partial rounded music preview patch detected")
    if has_import:
        return text

    imports = list(re.finditer(r"(?m)^import .+$", text))
    if not imports:
        raise PatchError("TopBar import anchor not found")
    import_block = f"\n{IMPORT_BEGIN}\nimport QtQuick.Effects\n{IMPORT_END}"
    text = text[: imports[-1].end()] + import_block + text[imports[-1].end() :]

    source_anchor = 'source: barWindow.displayArtUrl || "";'
    source_index = text.find(source_anchor)
    if source_index < 0:
        raise PatchError("music preview image anchor not found")
    image_start = text.rfind("Image {", 0, source_index)
    opening = text.find("{", image_start)
    image_end = find_matching_brace(text, opening) + 1
    line_start = text.rfind("\n", 0, image_start) + 1
    indent = text[line_start:image_start]
    art_block = f'''{indent}{ART_BEGIN}
{indent}Image {{
{indent}    id: musicPreviewArt
{indent}    anchors.fill: parent
{indent}    source: barWindow.displayArtUrl || ""
{indent}    fillMode: Image.PreserveAspectCrop
{indent}    visible: false
{indent}}}
{indent}Rectangle {{
{indent}    id: musicPreviewMask
{indent}    anchors.fill: parent
{indent}    radius: barWindow.s(8)
{indent}    visible: false
{indent}    layer.enabled: true
{indent}}}
{indent}MultiEffect {{
{indent}    anchors.fill: parent
{indent}    source: musicPreviewArt
{indent}    maskEnabled: true
{indent}    maskSource: musicPreviewMask
{indent}    visible: musicPreviewArt.status === Image.Ready
{indent}}}
{indent}{ART_END}'''
    text = text[:line_start] + art_block + text[image_end:]

    tint_pattern = re.compile(
        r'(?P<indent>\s*)Rectangle\s*\{\s*\n'
        r'(?P=indent)\s+anchors\.fill:\s*parent\s*\n'
        r'(?P=indent)\s+color:\s*Qt\.rgba\(mocha\.mauve\.r,\s*mocha\.mauve\.g,\s*mocha\.mauve\.b,\s*0\.2\)\s*\n'
        r'(?P=indent)\}',
    )
    tint_match = tint_pattern.search(text, line_start)
    if not tint_match:
        raise PatchError("music preview tint anchor not found")
    tint_indent = tint_match.group("indent")
    tint_block = (
        f"{tint_indent}Rectangle {{\n"
        f"{tint_indent}    anchors.fill: parent\n"
        f"{tint_indent}    radius: barWindow.s(8)\n"
        f"{tint_indent}    color: Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.2)\n"
        f"{tint_indent}}}"
    )
    return text[: tint_match.start()] + tint_block + text[tint_match.end() :]


def patch_visualizer_controls(text: str) -> str:
    if VISUALIZER_BEGIN in text:
        if VISUALIZER_END not in text:
            raise PatchError("partial music visualizer controls patch detected")
        return text

    previous_anchor = 'Quickshell.execDetached(["playerctl", "previous"])'
    previous_index = text.find(previous_anchor)
    if previous_index < 0:
        raise PatchError("top bar previous button anchor not found")
    row_start = text.rfind("Row {", 0, previous_index)
    opening = text.find("{", row_start)
    row_end = find_matching_brace(text, opening) + 1
    controls = text[row_start:row_end]
    if 'Quickshell.execDetached(["playerctl", "next"])' not in controls:
        raise PatchError("top bar playback controls row not found")
    line_start = text.rfind("\n", 0, row_start) + 1
    indent = text[line_start:row_start]
    controls_indent = indent + "    "
    controls = controls.replace(
        "Row {",
        "Row {\n"
        f"{controls_indent}visible: !MusicVisualizerData.enabled || !MusicVisualizerData.available",
        1,
    )
    visualizer = f'''{indent}{VISUALIZER_BEGIN}
{indent}MusicVisualizer {{
{indent}    visible: MusicVisualizerData.enabled && MusicVisualizerData.available
{indent}    uiScale: barWindow.s(1)
{indent}    primaryColor: mocha.mauve
{indent}    secondaryColor: mocha.blue
{indent}    backgroundColor: mocha.surface0
{indent}    onActivated: {{
{indent}        Quickshell.execDetached(["playerctl", "play-pause"])
{indent}        musicForceRefresh.running = true
{indent}    }}
{indent}}}
{indent}{VISUALIZER_END}
{indent}'''
    return text[:line_start] + visualizer + controls + text[row_end:]


def patch_topbar(text: str) -> str:
    return patch_visualizer_controls(patch_rounded_art(text))


def patch_settings_popup(text: str) -> str:
    present = [name for name in POPUP_MARKERS if f"BEGIN user-addon: {name}" in text]
    if present:
        if len(present) != len(POPUP_MARKERS):
            raise PatchError("partial music visualizer Settings patch detected")
        return text

    cards = list(re.finditer(r"(?m)^\s*\{\s*tab:\s*0,\s*boxIndex:\s*(\d+).*?$", text))
    max_match = re.search(r"(?m)^(?P<indent>\s*)if \(tab === 0\) return (?P<index>\d+);\s*$", text)
    if not cards or not max_match:
        raise PatchError("General settings index anchors not found")
    addon_index = max(max(int(item.group(1)) for item in cards), int(max_match.group("index"))) + 1

    imports = list(re.finditer(r"(?m)^import .+$", text))
    import_block = (
        "\n// BEGIN user-addon: music-visualizer import\n"
        'import "." as MusicVisualizerSettings\n'
        "// END user-addon: music-visualizer import"
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
        f"{indent}// BEGIN user-addon: music-visualizer keyboard-toggle\n"
        f"{indent} else if (root.highlightedBox === {addon_index}) {{\n"
        f"{indent}    if (generalLoader.item) generalLoader.item.toggleMusicVisualizer();\n"
        f"{indent}}}\n"
        f"{indent}// END user-addon: music-visualizer keyboard-toggle\n"
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
        f"\n{indent}// BEGIN user-addon: music-visualizer general-toggle\n"
        f"{indent}function toggleMusicVisualizer() {{ musicVisualizerCard.toggle(); }}\n"
        f"{indent}// END user-addon: music-visualizer general-toggle"
    )
    text = text[: function_anchor.end()] + function_block + text[function_anchor.end() :]

    tab_one_card = re.search(r"(?m)^\s*\{\s*tab:\s*1,\s*boxIndex:", text)
    card_indent = re.match(r"\s*", tab_one_card.group(0)).group(0)
    search_block = (
        f"{card_indent}// BEGIN user-addon: music-visualizer search-card\n"
        f'{card_indent}{{ tab: 0, boxIndex: {addon_index}, label: "Music visualizer", '
        'desc: "Replace playback controls with CAVA", icon: "󰎆", color: "mauve" },\n'
        f"{card_indent}// END user-addon: music-visualizer search-card\n"
    )
    text = text[: tab_one_card.start()] + search_block + text[tab_one_card.start() :]

    main_column = re.search(r"ColumnLayout\s*\{\s*\n\s*id:\s*settingsMainCol\b", text)
    if not main_column:
        raise PatchError("General settings column not found")
    opening = text.find("{", main_column.start())
    closing = find_matching_brace(text, opening)
    card_block = (
        "\n                    // BEGIN user-addon: music-visualizer card\n"
        "                    MusicVisualizerSettings.MusicVisualizerCard {\n"
        "                        id: musicVisualizerCard\n"
        "                        uiScale: root.s(1)\n"
        f"                        highlighted: root.highlightedBox === {addon_index}\n"
        "                        accentColor: root.mauve\n"
        "                        baseColor: root.base\n"
        "                        textColor: root.text\n"
        "                        subtextColor: root.subtext0\n"
        "                        surface0Color: root.surface0\n"
        "                        surface1Color: root.surface1\n"
        "                        surface2Color: root.surface2\n"
        "                        settingsPath: Config.settingsJsonPath\n"
        f"                        onSelected: root.highlightedBox = {addon_index}\n"
        "                    }\n"
        "                    // END user-addon: music-visualizer card\n"
        "                "
    )
    return text[:closing] + card_block + text[closing:]


def replace_once(text: str, old: str, new: str, description: str) -> str:
    if text.count(old) != 1:
        raise PatchError(f"addon category anchor not found: {description}")
    return text.replace(old, new, 1)


def patch_addon_category(text: str) -> str:
    if ADDON_CATEGORY_BEGIN in text:
        if ADDON_CATEGORY_END not in text:
            raise PatchError("partial Addons category patch detected")
        return text

    required_markers = (
        "matugen-vibrant card",
        "screenshot-freeze card",
        "music-visualizer card",
    )
    if any(f"BEGIN user-addon: {marker}" not in text for marker in required_markers):
        raise PatchError("all addon setting cards must be installed before creating the Addons tab")

    max_match = re.search(r"(?m)^(?P<indent>\s*)if \(tab === 0\) return \d+;\s*$", text)
    if not max_match:
        raise PatchError("General maximum index not found")
    indent = max_match.group("indent")
    max_block = f"{indent}if (tab === 0) return 6;\n{indent}if (tab === 5) return 2;"
    text = text[: max_match.start()] + max_block + text[max_match.end() :]

    tab_properties = (
        '    property var tabNames: ["General", "Weather", "Keybinds", "Monitors", "Startup"]\n'
        '    property var tabIcons: ["󰒓", "󰖐", "󰌌", "󰍹", "󰐥"]\n'
        '    property var tabColors: ["teal", "blue", "peach", "green", "mauve"]'
    )
    category_properties = (
        f"    {ADDON_CATEGORY_BEGIN}\n"
        '    property var tabNames: ["General", "Weather", "Keybinds", "Monitors", "Startup", "Addons"]\n'
        '    property var tabIcons: ["󰒓", "󰖐", "󰌌", "󰍹", "󰐥", "󰏖"]\n'
        '    property var tabColors: ["teal", "blue", "peach", "green", "mauve", "sapphire"]\n'
        f"    {ADDON_CATEGORY_END}"
    )
    text = replace_once(text, tab_properties, category_properties, "tab metadata")
    text = replace_once(
        text,
        "    property bool tab4Loaded: false",
        "    property bool tab4Loaded: false\n    property bool tab5Loaded: false",
        "Addons loaded state",
    )
    text = replace_once(
        text,
        "        else if (currentTab === 4) root.tab4Loaded = true;",
        "        else if (currentTab === 4) root.tab4Loaded = true;\n        else if (currentTab === 5) root.tab5Loaded = true;",
        "Addons tab loading",
    )
    text = replace_once(
        text,
        "        root.currentTab = (root.currentTab + 1) % 5;",
        "        root.currentTab = (root.currentTab + 1) % root.tabNames.length;",
        "forward tab cycling",
    )
    text = replace_once(
        text,
        "        root.currentTab = (root.currentTab + 4) % 5;",
        "        root.currentTab = (root.currentTab + root.tabNames.length - 1) % root.tabNames.length;",
        "backward tab cycling",
    )

    activation_anchor = "        } else if (root.currentTab === 1) {"
    activation_block = (
        "        } else if (root.currentTab === 5) {\n"
        "            if (root.highlightedBox === 0 && addonsLoader.item) addonsLoader.item.toggleVibrantMatugen();\n"
        "            else if (root.highlightedBox === 1 && addonsLoader.item) addonsLoader.item.toggleScreenshotFreeze();\n"
        "            else if (root.highlightedBox === 2 && addonsLoader.item) addonsLoader.item.toggleMusicVisualizer();\n"
        "        } else if (root.currentTab === 1) {"
    )
    text = replace_once(text, activation_anchor, activation_block, "Addons keyboard activation")

    scroll_anchor = "        } else if (root.currentTab === 1 && weatherLoader.item) {"
    scroll_block = (
        "        } else if (root.currentTab === 5 && addonsLoader.item) {\n"
        "            addonsLoader.item.scrollToBox(box);\n"
        "        } else if (root.currentTab === 1 && weatherLoader.item) {"
    )
    text = replace_once(text, scroll_anchor, scroll_block, "Addons keyboard scrolling")

    jump_anchor = "                } else if (targetTab === 1 && weatherLoader.item) {"
    jump_block = (
        "                } else if (targetTab === 5 && addonsLoader.item) {\n"
        "                    addonsLoader.item.scrollToBox(targetBox);\n"
        "                } else if (targetTab === 1 && weatherLoader.item) {"
    )
    text = replace_once(text, jump_anchor, jump_block, "Addons search navigation")

    search_replacements = (
        (
            r'\{ tab: 0, boxIndex: \d+, label: "Vibrant Matugen colors"',
            '{ tab: 5, boxIndex: 0, label: "Vibrant Matugen colors"',
        ),
        (
            r'\{ tab: 0, boxIndex: \d+, label: "Freeze screen during selection"',
            '{ tab: 5, boxIndex: 1, label: "Freeze screen during selection"',
        ),
        (
            r'\{ tab: 0, boxIndex: \d+, label: "Music visualizer"',
            '{ tab: 5, boxIndex: 2, label: "Music visualizer"',
        ),
    )
    for pattern, replacement in search_replacements:
        text, count = re.subn(pattern, replacement, text, count=1)
        if count != 1:
            raise PatchError("addon search card could not be moved")

    hidden_cards = (
        "MatugenVibrant.VibrantMatugenCard {",
        "ScreenshotFreeze.ScreenshotFreezeCard {",
        "MusicVisualizerSettings.MusicVisualizerCard {",
    )
    for opening_line in hidden_cards:
        replacement = opening_line + "\n                        visible: false"
        text = replace_once(text, opening_line, replacement, f"hide {opening_line}")

    text = replace_once(
        text,
        "                        highlighted: root.highlightedBox === 7",
        "                        highlighted: false",
        "hidden Matugen highlight",
    )
    text = replace_once(
        text,
        "                        highlighted: root.highlightedBox === 8",
        "                        highlighted: false",
        "hidden screenshot highlight",
    )
    text = replace_once(
        text,
        "                        highlighted: root.highlightedBox === 9",
        "                        highlighted: false",
        "hidden visualizer highlight",
    )

    text = replace_once(
        text,
        "                        visible: root.currentTab !== 2 && root.currentTab !== 4 && !root.isSearchMode",
        "                        visible: root.currentTab !== 2 && root.currentTab !== 4 && root.currentTab !== 5 && !root.isSearchMode",
        "hide Save on Addons",
    )
    text = replace_once(
        text,
        "                            property color c4: root.mauve",
        "                            property color c4: root.mauve\n                            property color c5: root.sapphire",
        "Addons tab highlight color",
    )
    text = replace_once(
        text,
        "                                if (root.currentTab === 3) return c3;\n                                return c4;",
        "                                if (root.currentTab === 3) return c3;\n                                if (root.currentTab === 4) return c4;\n                                return c5;",
        "Addons highlight selection",
    )

    monitors_loader = "                    Loader {\n                        id: monitorsLoader"
    addons_loader = '''                    Loader {
                        id: addonsLoader
                        anchors.fill: parent
                        active: root.tab5Loaded && Config.dataReady
                        visible: root.currentTab === 5 && !root.isSearchMode
                        opacity: visible ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                        sourceComponent: Component {
                            AddonSettingsPage {
                                uiScale: root.s(1)
                                highlightedBox: root.highlightedBox
                                settingsPath: Config.settingsJsonPath
                                tealColor: root.teal
                                blueColor: root.blue
                                mauveColor: root.mauve
                                baseColor: root.base
                                textColor: root.text
                                subtextColor: root.subtext0
                                surface0Color: root.surface0
                                surface1Color: root.surface1
                                surface2Color: root.surface2
                                onSelected: index => root.highlightedBox = index
                            }
                        }
                    }

                    Loader {
                        id: monitorsLoader'''
    text = replace_once(text, monitors_loader, addons_loader, "Addons loader")
    return text


def patch_settings_with_category(text: str) -> str:
    return patch_addon_category(patch_settings_popup(text))


def atomic_write(path: Path, content: str) -> None:
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
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    shutil.copy2(path, BACKUP_DIR / f"{path.name}.{stamp}")


def validate_qml(path: Path) -> None:
    result = subprocess.run(["qmllint", str(path)], capture_output=True, text=True)
    if result.returncode:
        raise PatchError((result.stdout + result.stderr).strip())


def install_assets() -> list[str]:
    changed = []
    for source, target in ASSETS.items():
        if not source.is_file():
            raise PatchError(f"addon asset not found: {source}")
        validate_qml(source)
        desired = source.read_bytes()
        if target.is_file() and target.read_bytes() == desired:
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_name(f".{target.name}.music-visualizer")
        shutil.copy2(source, temporary)
        os.replace(temporary, target)
        changed.append(target.name)
    return changed


def patch_file(path: Path, patcher) -> bool:
    if not path.is_file():
        raise PatchError(f"upstream file not found: {path}")
    original = path.read_text(encoding="utf-8")
    patched = patcher(original)
    if patched == original:
        validate_qml(path)
        return False
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent, text=True)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(patched)
        os.chmod(temporary, path.stat().st_mode)
        validate_qml(temporary)
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
    requested = False if enabled is None else enabled
    if "musicVisualizerEnabled" in data and enabled is None:
        return False
    if data.get("musicVisualizerEnabled") is requested:
        return False
    data["musicVisualizerEnabled"] = requested
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
    parser = argparse.ArgumentParser(description="Install and manage the top bar music visualizer")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--enable", action="store_true")
    group.add_argument("--disable", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not shutil.which("qmllint"):
        raise PatchError("missing required command: qmllint")
    for path in (TOPBAR, SETTINGS_POPUP, SETTINGS):
        if not path.is_file():
            raise PatchError(f"required upstream file not found: {path}")
    if not (ADDON_DIR / "cava.conf").is_file():
        raise PatchError("CAVA configuration asset is missing")

    LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)
    with LOCK_FILE.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        explicit = True if args.enable else False if args.disable else None
        changes = []
        if write_enabled(explicit):
            changes.append("saved option")
        asset_changes = install_assets()
        if asset_changes:
            changes.append("visualizer assets")
        if patch_file(TOPBAR, patch_topbar):
            changes.append("top bar")
        if patch_file(SETTINGS_POPUP, patch_settings_with_category):
            changes.append("settings UI")
        if changes:
            reload_quickshell()
            print("music-preview-rounded: updated " + ", ".join(changes))
        else:
            print("music-preview-rounded: addon already installed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"music-preview-rounded: {error}; no further changes applied", file=os.sys.stderr)
        raise SystemExit(1)
