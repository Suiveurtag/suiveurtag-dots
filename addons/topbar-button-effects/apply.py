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
MAIN_QML = Path(os.environ.get("TOPBAR_EFFECTS_MAIN", QS_DIR / "Main.qml")).expanduser()
TOPBAR_QML = Path(os.environ.get("TOPBAR_EFFECTS_TOPBAR", QS_DIR / "TopBar.qml")).expanduser()
SETTINGS_POPUP = Path(
    os.environ.get("TOPBAR_EFFECTS_SETTINGS_POPUP", QS_DIR / "settings/SettingsPopup.qml")
).expanduser()
ADDON_SETTINGS_PAGE = Path(
    os.environ.get("TOPBAR_EFFECTS_ADDON_SETTINGS", QS_DIR / "settings/AddonSettingsPage.qml")
).expanduser()
SETTINGS = Path(os.environ.get("HYPR_SETTINGS", HYPR_BASE / "settings.json")).expanduser()
SHELL_QML = QS_DIR / "Shell.qml"
ADDON_DIR = XDG_DATA_HOME / "quickshell-addons/topbar-button-effects"
BACKUP_DIR = ADDON_DIR / "backups"
LOCK_FILE = XDG_RUNTIME_DIR / "quickshell-addons-settings.lock"

ASSETS = {
    ADDON_DIR / "TopBarButtonEffect.qml": QS_DIR / "TopBarButtonEffect.qml",
    ADDON_DIR / "TopBarButtonEffectsCard.qml": SETTINGS_POPUP.parent / "TopBarButtonEffectsCard.qml",
}

MAIN_BEGIN = "// BEGIN user-addon: topbar-button-effects widget-state"
MAIN_END = "// END user-addon: topbar-button-effects widget-state"
TOPBAR_STATE_BEGIN = "// BEGIN user-addon: topbar-button-effects state"
TOPBAR_STATE_END = "// END user-addon: topbar-button-effects state"
TOPBAR_READER_BEGIN = "// BEGIN user-addon: topbar-button-effects settings-reader"
TOPBAR_READER_END = "// END user-addon: topbar-button-effects settings-reader"
TOPBAR_WIDGET_BEGIN = "// BEGIN user-addon: topbar-button-effects widget-reader"
TOPBAR_WIDGET_END = "// END user-addon: topbar-button-effects widget-reader"
SETTINGS_BEGIN = "// BEGIN user-addon: topbar-button-effects settings"
SETTINGS_END = "// END user-addon: topbar-button-effects settings"
PAGE_BEGIN = "// BEGIN user-addon: topbar-button-effects card"
PAGE_END = "// END user-addon: topbar-button-effects card"


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


def replace_once(text: str, old: str, new: str, description: str) -> str:
    if text.count(old) != 1:
        raise PatchError(f"anchor not found: {description}")
    return text.replace(old, new, 1)


def patch_main(text: str) -> str:
    if MAIN_BEGIN in text:
        if MAIN_END not in text:
            raise PatchError("partial main widget-state patch detected")
        return text

    old = '''    onCurrentActiveChanged: {
        Quickshell.execDetached(["bash", "-c", "echo '" + currentActive + "' > " + paths.runDir + "/current_widget"]);
    }

    property bool isVisible: false
    property string activeArg: ""'''
    new = f'''    {MAIN_BEGIN}
    function writeCurrentWidgetState() {{
        Quickshell.execDetached([
            "bash", "-c", "printf '%s\\\\n%s\\\\n' \\"$1\\" \\"$2\\" > \\"$3\\"",
            "_", currentActive, activeArg, paths.runDir + "/current_widget"
        ]);
    }}

    onCurrentActiveChanged: writeCurrentWidgetState()

    property bool isVisible: false
    property string activeArg: ""
    onActiveArgChanged: writeCurrentWidgetState()
    {MAIN_END}'''
    return replace_once(text, old, new, "Main current widget state")


def effect_block(indent: str, effect_id: str, mouse_id: str, active_expression: str) -> str:
    return f'''{indent}{TOPBAR_STATE_BEGIN} {effect_id}
{indent}TopBarButtonEffect {{
{indent}    id: {effect_id}
{indent}    anchors.fill: parent
{indent}    effectEnabled: barWindow.topbarButtonAnimations
{indent}    active: {active_expression}
{indent}    pressed: {mouse_id}.pressed
{indent}    cornerRadius: parent.radius
{indent}    palette: barWindow.topbarButtonEffectPalette
{indent}    pressColor: mocha.surface2
{indent}}}
{indent}{TOPBAR_STATE_END} {effect_id}
'''


def patch_button_container(
    text: str,
    anchor: str,
    effect_id: str,
    mouse_id: str,
    active_expression: str,
    hover_expression: str = "1.0",
) -> str:
    if f"{TOPBAR_STATE_BEGIN} {effect_id}" in text:
        if f"{TOPBAR_STATE_END} {effect_id}" not in text:
            raise PatchError(f"partial top bar effect detected: {effect_id}")
        return text

    anchor_index = text.find(anchor)
    if anchor_index < 0:
        raise PatchError(f"top bar button anchor not found: {anchor}")
    rectangle_start = text.rfind("Rectangle {", 0, anchor_index)
    if rectangle_start < 0:
        raise PatchError(f"top bar Rectangle not found: {anchor}")
    opening = text.find("{", rectangle_start)
    closing = find_matching_brace(text, opening)
    line_start = text.rfind("\n", 0, rectangle_start) + 1
    base_indent = text[line_start:rectangle_start]
    child_indent = base_indent + "    "
    block = text[rectangle_start : closing + 1]

    direct_scale = re.compile(rf"(?m)^{re.escape(child_indent)}scale:\s*.+\n")
    block = direct_scale.sub("", block)

    local_anchor = block.find(anchor)
    line_end = block.find("\n", local_anchor)
    if line_end < 0:
        raise PatchError(f"top bar scale insertion point not found: {anchor}")
    scale = f"\n{child_indent}scale: {effect_id}.visualScale * ({hover_expression})"
    block = block[:line_end] + scale + block[line_end:]

    local_closing = len(block) - 1
    visual = effect_block(child_indent, effect_id, mouse_id, active_expression)
    block = block[:local_closing] + "\n" + visual + base_indent + block[local_closing:]
    return text[:rectangle_start] + block + text[closing + 1 :]


def patch_topbar(text: str) -> str:
    text = re.sub(
        r'active: barWindow\.activeWidget === "network" && '
        r'(?:barWindow\.activeWidgetArg !== "bt"|'
        r'\(barWindow\.activeWidgetArg !== "bt" \|\| barWindow\.isDesktop\))',
        'active: barWindow.activeWidget === "network" && '
        '(barWindow.activeWidgetArg !== "bt" || barWindow.isDesktop)',
        text,
        count=1,
    )
    text = re.sub(
        r'active: barWindow\.activeWidget === "network" && '
        r'barWindow\.activeWidgetArg === "bt"(?: && !barWindow\.isDesktop)*',
        'active: barWindow.activeWidget === "network" && '
        'barWindow.activeWidgetArg === "bt" && !barWindow.isDesktop',
        text,
        count=1,
    )

    if TOPBAR_STATE_BEGIN not in text:
        state_anchor = '''            property string activeWidget: ""
            property bool isSettingsOpen: activeWidget === "settings"'''
        state_block = f'''            {TOPBAR_STATE_BEGIN}
            property bool topbarButtonAnimations: true
            property string activeWidgetArg: ""
            property var topbarButtonEffectPalette: [mocha.blue, mocha.mauve, mocha.pink, mocha.peach, mocha.teal]
            {TOPBAR_STATE_END}

{state_anchor}'''
        text = replace_once(text, state_anchor, state_block, "TopBar animation state")

    if TOPBAR_WIDGET_BEGIN not in text:
        old = '''                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (barWindow.activeWidget !== txt) barWindow.activeWidget = txt;
                    }'''
        new = f'''                    onStreamFinished: {{
                        {TOPBAR_WIDGET_BEGIN}
                        const lines = this.text.split("\\n");
                        const widget = (lines[0] || "").trim();
                        const widgetArg = (lines[1] || "").trim();
                        if (barWindow.activeWidget !== widget) barWindow.activeWidget = widget;
                        if (barWindow.activeWidgetArg !== widgetArg) barWindow.activeWidgetArg = widgetArg;
                        {TOPBAR_WIDGET_END}
                    }}'''
        text = replace_once(text, old, new, "TopBar current widget reader")

    if TOPBAR_READER_BEGIN not in text:
        anchor = '''                                if (parsed.workspaceCount !== undefined && barWindow.workspaceCount !== parsed.workspaceCount) {'''
        block = f'''                                {TOPBAR_READER_BEGIN}
                                if (parsed.topbarButtonAnimations !== undefined) {{
                                    barWindow.topbarButtonAnimations = parsed.topbarButtonAnimations;
                                }}
                                {TOPBAR_READER_END}

{anchor}'''
        text = replace_once(text, anchor, block, "TopBar settings reader")

    buttons = (
        (
            "property bool isHovered: helpMouse.containsMouse",
            "helpButtonEffect",
            "helpMouse",
            'barWindow.activeWidget === "guide"',
            "1.0",
        ),
        (
            "property bool isHovered: searchMouse.containsMouse",
            "searchButtonEffect",
            "searchMouse",
            'barWindow.activeWidget === "applauncher"',
            "1.0",
        ),
        (
            "property bool isHovered: settingsMouse.containsMouse",
            "settingsButtonEffect",
            "settingsMouse",
            'barWindow.activeWidget === "settings"',
            "1.0",
        ),
        (
            "id: updateButton",
            "updateButtonEffect",
            "updateMouse",
            'barWindow.activeWidget === "updater"',
            "1.0",
        ),
        (
            "id: mediaBox",
            "musicButtonEffect",
            "mediaInfoMouse",
            'barWindow.activeWidget === "music"',
            "1.0",
        ),
        (
            "id: centerBox",
            "calendarButtonEffect",
            "centerMouse",
            'barWindow.activeWidget === "calendar"',
            "centerBox.isHovered ? 1.03 : 1.0",
        ),
        (
            "property bool isHovered: kbMouse.containsMouse",
            "keyboardButtonEffect",
            "kbMouse",
            "false",
            "isHovered ? 1.05 : 1.0",
        ),
        (
            "id: wifiPill",
            "networkButtonEffect",
            "wifiMouse",
            'barWindow.activeWidget === "network" && (barWindow.activeWidgetArg !== "bt" || barWindow.isDesktop)',
            "isHovered ? 1.05 : 1.0",
        ),
        (
            "id: btPill",
            "bluetoothButtonEffect",
            "btMouse",
            'barWindow.activeWidget === "network" && barWindow.activeWidgetArg === "bt" && !barWindow.isDesktop',
            "isHovered ? 1.05 : 1.0",
        ),
        (
            "property bool isHovered: volMouse.containsMouse",
            "volumeButtonEffect",
            "volMouse",
            'barWindow.activeWidget === "volume"',
            "isHovered ? 1.05 : 1.0",
        ),
        (
            "property bool isHovered: batMouse.containsMouse",
            "batteryButtonEffect",
            "batMouse",
            'barWindow.activeWidget === "battery"',
            "isHovered ? 1.05 : 1.0",
        ),
    )
    for arguments in buttons:
        text = patch_button_container(text, *arguments)
    return text


def patch_addon_settings_page(text: str) -> str:
    if PAGE_BEGIN in text:
        if PAGE_END not in text:
            raise PatchError("partial Addons page animation card detected")
        return text

    function_anchor = "    function toggleIdleInhibit() { idleInhibitCard.toggle(); }"
    function_block = (
        function_anchor
        + "\n"
        + "    function toggleTopBarButtonEffects() { topbarButtonEffectsCard.toggle(); }"
    )
    text = replace_once(text, function_anchor, function_block, "Addons page toggle function")

    color_anchor = '    property color sapphireColor: "#74c7ec"'
    text = replace_once(
        text,
        color_anchor,
        color_anchor + '\n    property color pinkColor: "#f5c2e7"',
        "Addons page pink color",
    )

    card_anchor = "            AddonCards.IdleInhibitCard {"
    card_start = text.find(card_anchor)
    if card_start < 0:
        raise PatchError("idle card anchor not found in Addons page")
    opening = text.find("{", card_start)
    closing = find_matching_brace(text, opening) + 1
    indent = text[text.rfind("\n", 0, card_start) + 1 : card_start]
    card = f'''

{indent}{PAGE_BEGIN}
{indent}AddonCards.TopBarButtonEffectsCard {{
{indent}    id: topbarButtonEffectsCard
{indent}    uiScale: root.uiScale
{indent}    highlighted: root.highlightedBox === 4
{indent}    accentColor: root.pinkColor
{indent}    baseColor: root.baseColor
{indent}    textColor: root.textColor
{indent}    subtextColor: root.subtextColor
{indent}    surface0Color: root.surface0Color
{indent}    surface1Color: root.surface1Color
{indent}    surface2Color: root.surface2Color
{indent}    settingsPath: root.settingsPath
{indent}    onSelected: root.selected(4)
{indent}}}
{indent}{PAGE_END}'''
    return text[:closing] + card + text[closing:]


def patch_settings_popup(text: str) -> str:
    if SETTINGS_BEGIN in text:
        if SETTINGS_END not in text:
            raise PatchError("partial Settings popup animation patch detected")
        return text

    text = replace_once(
        text,
        "        if (tab === 5) return 3;",
        "        if (tab === 5) return 4;",
        "Addons maximum index",
    )

    activation_anchor = (
        "            else if (root.highlightedBox === 3 && addonsLoader.item) "
        "addonsLoader.item.toggleIdleInhibit();"
    )
    activation = (
        activation_anchor
        + "\n"
        + "            else if (root.highlightedBox === 4 && addonsLoader.item) "
        "addonsLoader.item.toggleTopBarButtonEffects();"
    )
    text = replace_once(text, activation_anchor, activation, "animation keyboard activation")

    search_anchor = "        // END user-addon: idle-inhibit search-card"
    search = f'''{search_anchor}
        {SETTINGS_BEGIN}
        {{ tab: 5, boxIndex: 4, label: "Animated top bar buttons", desc: "Press feedback and flowing Matugen outlines", icon: "󰆾", color: "pink" }},
        {SETTINGS_END}'''
    text = replace_once(text, search_anchor, search, "animation search card")

    loader_anchor = "                                mauveColor: root.mauve"
    loader = loader_anchor + "\n                                pinkColor: root.pink"
    return replace_once(text, loader_anchor, loader, "Addons page Matugen pink")


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
        temporary = target.with_name(f".{target.name}.topbar-button-effects")
        shutil.copy2(source, temporary)
        os.replace(temporary, target)
        changed.append(target.name)
    return changed


def patch_file(path: Path, patcher, validate: bool = True) -> bool:
    if not path.is_file():
        raise PatchError(f"upstream file not found: {path}")
    original = path.read_text(encoding="utf-8")
    patched = patcher(original)
    if patched == original:
        if validate:
            validate_qml(path)
        return False
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent, text=True)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(patched)
        os.chmod(temporary, path.stat().st_mode)
        if validate:
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
    requested = True if enabled is None else enabled
    if "topbarButtonAnimations" in data and enabled is None:
        return False
    if data.get("topbarButtonAnimations") is requested:
        return False
    data["topbarButtonAnimations"] = requested
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
    parser = argparse.ArgumentParser(description="Install and manage animated top bar buttons")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--enable", action="store_true")
    group.add_argument("--disable", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not shutil.which("qmllint"):
        raise PatchError("missing required command: qmllint")
    for path in (MAIN_QML, TOPBAR_QML, SETTINGS_POPUP, ADDON_SETTINGS_PAGE, SETTINGS):
        if not path.is_file():
            raise PatchError(f"required upstream file not found: {path}")

    LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)
    with LOCK_FILE.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        explicit = True if args.enable else False if args.disable else None
        changes = []
        if write_enabled(explicit):
            changes.append("saved option")
        assets = install_assets()
        if assets:
            changes.append("animation assets")
        # The upstream Main.qml currently makes qmllint exit 255 without
        # diagnostics even before this patch, so keep this small state writer
        # patch structural and validate the remaining QML files normally.
        if patch_file(MAIN_QML, patch_main, validate=False):
            changes.append("panel state")
        if patch_file(TOPBAR_QML, patch_topbar):
            changes.append("top bar")
        if patch_file(ADDON_SETTINGS_PAGE, patch_addon_settings_page):
            changes.append("Addons page")
        if patch_file(SETTINGS_POPUP, patch_settings_popup):
            changes.append("settings UI")
        if changes:
            reload_quickshell()
            print("topbar-button-effects: updated " + ", ".join(changes))
        else:
            print("topbar-button-effects: addon already installed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"topbar-button-effects: {error}; no further changes applied", file=os.sys.stderr)
        raise SystemExit(1)
