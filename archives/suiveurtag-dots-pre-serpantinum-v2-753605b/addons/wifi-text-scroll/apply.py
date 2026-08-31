#!/usr/bin/env python3

from __future__ import annotations

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
HYPR_BASE = Path(os.environ.get("HYPR_CONFIG_DIR", XDG_CONFIG_HOME / "hypr")).expanduser()
QS_DIR = Path(os.environ.get("HYPR_QUICKSHELL_DIR", HYPR_BASE / "scripts/quickshell")).expanduser()
NETWORK_POPUP = Path(
    os.environ.get("WIFI_TEXT_SCROLL_NETWORK_POPUP", QS_DIR / "network/NetworkPopup.qml")
).expanduser()
SHELL_QML = QS_DIR / "Shell.qml"
ADDON_DIR = XDG_DATA_HOME / "quickshell-addons/wifi-text-scroll"
BACKUP_DIR = ADDON_DIR / "backups"

STATE_BEGIN = "// BEGIN user-addon: wifi-text-scroll active-ssid-state"
STATE_END = "// END user-addon: wifi-text-scroll active-ssid-state"
BASE_BEGIN = "// BEGIN user-addon: wifi-text-scroll active-ssid-base"
BASE_END = "// END user-addon: wifi-text-scroll active-ssid-base"
FILL_BEGIN = "// BEGIN user-addon: wifi-text-scroll active-ssid-fill"
FILL_END = "// END user-addon: wifi-text-scroll active-ssid-fill"

ACTIVE_NAME = (
    'coreContainer.myDevice ? (window.activeMode === "wifi" ? '
    'coreContainer.myDevice.ssid : coreContainer.myDevice.name) : ""'
)


class PatchError(RuntimeError):
    pass


def find_matching_brace(text: str, opening: int) -> int:
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


def replace_text_block(
    text: str,
    *,
    start_at: int,
    begin: str,
    end: str,
    block_factory,
) -> tuple[str, int]:
    present = [marker for marker in (begin, end) if marker in text]
    if present:
        if len(present) != 2:
            raise PatchError(f"partial marker pair: {begin}")
        return text, text.index(end) + len(end)

    anchor = f"text: {ACTIVE_NAME}"
    anchor_index = text.find(anchor, start_at)
    if anchor_index < 0:
        raise PatchError(f"active Wi-Fi name anchor not found after offset {start_at}")
    component_start = text.rfind("Text {", start_at, anchor_index)
    if component_start < 0:
        raise PatchError("active Wi-Fi Text component not found")
    opening = text.find("{", component_start)
    closing = find_matching_brace(text, opening)
    original = text[component_start : closing + 1]
    if "elide: Text.ElideRight" not in original:
        raise PatchError("active Wi-Fi text no longer has the expected elision")

    line_start = text.rfind("\n", 0, component_start) + 1
    indent = text[line_start:component_start]
    block = block_factory(indent)
    marked = f"{indent}{begin}\n{block}\n{indent}{end}"
    patched = text[:line_start] + marked + text[closing + 1 :]
    return patched, line_start + len(marked)


def base_name_block(indent: str) -> str:
    child = indent + "    "
    grandchild = child + "    "
    return f'''{indent}Item {{
{child}id: activeWifiNameBaseClip
{child}Layout.alignment: Qt.AlignHCenter
{child}Layout.preferredWidth: Math.min(activeWifiNameBaseText.implicitWidth, coreContainer.activeNameMaximumWidth)
{child}Layout.maximumWidth: coreContainer.activeNameMaximumWidth
{child}implicitHeight: activeWifiNameBaseText.implicitHeight
{child}clip: true

{child}Text {{
{grandchild}id: activeWifiNameBaseText
{grandchild}x: coreContainer.activeNameOffset
{grandchild}anchors.verticalCenter: parent.verticalCenter
{grandchild}width: window.activeMode === "wifi" ? implicitWidth : parent.width
{grandchild}horizontalAlignment: Text.AlignHCenter
{grandchild}font.family: "JetBrains Mono"
{grandchild}font.weight: Font.Black
{grandchild}font.pixelSize: window.s(16) - (window.s(4) * coreContainer.multiShift)
{grandchild}color: isMyDisconnecting ? window.overlay1 : window.crust
{grandchild}text: {ACTIVE_NAME}
{grandchild}elide: window.activeMode === "wifi" ? Text.ElideNone : Text.ElideRight
{grandchild}Behavior on color {{ ColorAnimation {{ duration: 200 }} }}
{child}}}

{child}Text {{
{grandchild}visible: coreContainer.scrollActiveWifiName
{grandchild}anchors.left: activeWifiNameBaseText.right
{grandchild}anchors.leftMargin: coreContainer.activeNameGap
{grandchild}anchors.verticalCenter: parent.verticalCenter
{grandchild}text: activeWifiNameBaseText.text
{grandchild}font: activeWifiNameBaseText.font
{grandchild}color: activeWifiNameBaseText.color
{child}}}
{indent}}}'''


def filled_name_block(indent: str) -> str:
    child = indent + "    "
    grandchild = child + "    "
    return f'''{indent}Item {{
{child}Layout.alignment: Qt.AlignHCenter
{child}Layout.preferredWidth: Math.min(activeWifiNameFilledText.implicitWidth, coreContainer.activeNameMaximumWidth)
{child}Layout.maximumWidth: coreContainer.activeNameMaximumWidth
{child}implicitHeight: activeWifiNameFilledText.implicitHeight
{child}clip: true

{child}Text {{
{grandchild}id: activeWifiNameFilledText
{grandchild}x: coreContainer.activeNameOffset
{grandchild}anchors.verticalCenter: parent.verticalCenter
{grandchild}width: window.activeMode === "wifi" ? implicitWidth : parent.width
{grandchild}horizontalAlignment: Text.AlignHCenter
{grandchild}font.family: "JetBrains Mono"
{grandchild}font.weight: Font.Black
{grandchild}font.pixelSize: window.s(16) - (window.s(4) * coreContainer.multiShift)
{grandchild}color: window.text
{grandchild}text: {ACTIVE_NAME}
{grandchild}elide: window.activeMode === "wifi" ? Text.ElideNone : Text.ElideRight
{child}}}

{child}Text {{
{grandchild}visible: coreContainer.scrollActiveWifiName
{grandchild}anchors.left: activeWifiNameFilledText.right
{grandchild}anchors.leftMargin: coreContainer.activeNameGap
{grandchild}anchors.verticalCenter: parent.verticalCenter
{grandchild}text: activeWifiNameFilledText.text
{grandchild}font: activeWifiNameFilledText.font
{grandchild}color: activeWifiNameFilledText.color
{child}}}
{indent}}}'''


def patch_network_popup(text: str) -> str:
    state_markers = [marker for marker in (STATE_BEGIN, STATE_END) if marker in text]
    if state_markers:
        if len(state_markers) != 2:
            raise PatchError("partial active Wi-Fi marquee state detected")
    else:
        anchor = (
            '                        property bool showEthDisconnected: isPrimary && '
            'window.currentPower && !window.currentConn && window.activeMode === "eth"'
        )
        if text.count(anchor) != 1:
            raise PatchError("active connection state anchor not found")
        state = f'''{anchor}

                        {STATE_BEGIN}
                        readonly property real activeNameMaximumWidth: window.s(150) - (window.s(50) * multiShift)
                        readonly property real activeNameGap: window.s(30)
                        readonly property bool scrollActiveWifiName: window.activeMode === "wifi"
                            && showConnected
                            && activeWifiNameBaseText.implicitWidth > activeWifiNameBaseClip.width + 0.5
                        property real activeNameOffset: 0

                        SequentialAnimation on activeNameOffset {{
                            running: coreContainer.scrollActiveWifiName
                            loops: Animation.Infinite
                            PauseAnimation {{ duration: 700 }}
                            NumberAnimation {{
                                from: 0
                                to: -(activeWifiNameBaseText.implicitWidth + coreContainer.activeNameGap)
                                duration: Math.max(1000, (activeWifiNameBaseText.implicitWidth + coreContainer.activeNameGap) * 35)
                                easing.type: Easing.Linear
                            }}
                        }}
                        onScrollActiveWifiNameChanged: if (!scrollActiveWifiName) activeNameOffset = 0
                        {STATE_END}'''
        text = text.replace(anchor, state, 1)

    text, position = replace_text_block(
        text,
        start_at=0,
        begin=BASE_BEGIN,
        end=BASE_END,
        block_factory=base_name_block,
    )
    text, _ = replace_text_block(
        text,
        start_at=position,
        begin=FILL_BEGIN,
        end=FILL_END,
        block_factory=filled_name_block,
    )
    return text


def validate_qml(path: Path) -> None:
    qmllint = shutil.which("qmllint")
    if not qmllint:
        raise PatchError("missing required command: qmllint")
    result = subprocess.run(
        [qmllint, "-I", str(QS_DIR), str(path)],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        details = (result.stdout + result.stderr).strip()
        raise PatchError(f"qmllint rejected {path.name}:\n{details}")


def backup(path: Path) -> None:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    shutil.copy2(path, BACKUP_DIR / f"{path.name}.{stamp}")


def patch_popup() -> bool:
    if not NETWORK_POPUP.is_file():
        raise PatchError(f"NetworkPopup not found: {NETWORK_POPUP}")
    original = NETWORK_POPUP.read_text(encoding="utf-8")
    patched = patch_network_popup(original)
    if patched == original:
        validate_qml(NETWORK_POPUP)
        return False

    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{NETWORK_POPUP.name}.", dir=NETWORK_POPUP.parent, text=True
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(patched)
        os.chmod(temporary, NETWORK_POPUP.stat().st_mode)
        validate_qml(temporary)
        backup(NETWORK_POPUP)
        os.replace(temporary, NETWORK_POPUP)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise
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


def main() -> int:
    if patch_popup():
        reload_quickshell()
        print("wifi-text-scroll: updated active Wi-Fi name")
    else:
        print("wifi-text-scroll: addon already installed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"wifi-text-scroll: {error}; no changes applied", file=os.sys.stderr)
        raise SystemExit(1)
