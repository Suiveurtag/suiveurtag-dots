#!/usr/bin/env python3

from __future__ import annotations

import os
import re
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
QS_DIR = Path(os.environ.get("HYPR_QUICKSHELL_DIR", HYPR_BASE / "scripts/quickshell")).expanduser()
VOLUME_POPUP = Path(
    os.environ.get("HEADSET_MIC_VOLUME_POPUP", QS_DIR / "volume" / "VolumePopup.qml")
).expanduser()
SHELL_QML = QS_DIR / "Shell.qml"
ADDON_DIR = XDG_DATA_HOME / "quickshell-addons" / "headset-mic-loopback"
COMPONENT = VOLUME_POPUP.parent / "HeadsetMicLoopbackCard.qml"
BACKUP_DIR = ADDON_DIR / "backups"

IMPORT_BEGIN = "// BEGIN user-addon: headset-mic-loopback import"
IMPORT_END = "// END user-addon: headset-mic-loopback import"
CARD_BEGIN = "// BEGIN user-addon: headset-mic-loopback card"
CARD_END = "// END user-addon: headset-mic-loopback card"


class PatchError(RuntimeError):
    pass


def patch_volume_popup(text: str) -> str:
    markers = (IMPORT_BEGIN, IMPORT_END, CARD_BEGIN, CARD_END)
    present = [marker for marker in markers if marker in text]
    if present:
        if len(present) != len(markers):
            raise PatchError("partial headset microphone patch detected")
        return text

    imports = list(re.finditer(r"(?m)^import .+$", text))
    if not imports:
        raise PatchError("VolumePopup import anchor not found")
    import_block = f'\n{IMPORT_BEGIN}\nimport "." as HeadsetMicLoopback\n{IMPORT_END}'
    text = text[: imports[-1].end()] + import_block + text[imports[-1].end() :]

    list_match = re.search(
        r"(?m)^(?P<indent>\s*)ListView\s*\{\s*\n"
        r"(?P=indent)\s+id:\s*contentList\s*\n"
        r"(?P=indent)\s+anchors\.fill:\s*parent\s*$",
        text,
    )
    if not list_match:
        raise PatchError("Streams list anchor not found")
    indent = list_match.group("indent")
    list_indent = indent + "    "
    card = f'''{indent}{CARD_BEGIN}
{indent}HeadsetMicLoopback.HeadsetMicLoopbackCard {{
{indent}    id: headsetMicLoopbackCard
{indent}    anchors.top: parent.top
{indent}    anchors.left: parent.left
{indent}    anchors.right: parent.right
{indent}    height: implicitHeight
{indent}    visible: window.activeTab === "apps"
{indent}    uiScale: window.s(1)
{indent}    accentColor: window.green
{indent}    baseColor: window.base
{indent}    textColor: window.text
{indent}    subtextColor: window.subtext0
{indent}    surface0Color: window.surface0
{indent}    surface1Color: window.surface1
{indent}    surface2Color: window.surface2
{indent}}}
{indent}{CARD_END}

{indent}ListView {{
{list_indent}id: contentList
{list_indent}anchors.top: window.activeTab === "apps" ? headsetMicLoopbackCard.bottom : parent.top
{list_indent}anchors.topMargin: window.activeTab === "apps" ? window.s(12) : 0
{list_indent}anchors.left: parent.left
{list_indent}anchors.right: parent.right
{list_indent}anchors.bottom: parent.bottom'''
    return text[: list_match.start()] + card + text[list_match.end() :]


def validate_qml(path: Path) -> None:
    result = subprocess.run(["qmllint", str(path)], capture_output=True, text=True)
    if result.returncode:
        raise PatchError((result.stdout + result.stderr).strip())


def install_component() -> bool:
    source = ADDON_DIR / "HeadsetMicLoopbackCard.qml"
    if not source.is_file():
        raise PatchError(f"addon component not found: {source}")
    validate_qml(source)
    if COMPONENT.is_file() and COMPONENT.read_bytes() == source.read_bytes():
        return False
    COMPONENT.parent.mkdir(parents=True, exist_ok=True)
    temporary = COMPONENT.with_name(f".{COMPONENT.name}.headset-mic-loopback")
    shutil.copy2(source, temporary)
    os.replace(temporary, COMPONENT)
    return True


def backup(path: Path) -> None:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    shutil.copy2(path, BACKUP_DIR / f"{path.name}.{stamp}")


def patch_popup() -> bool:
    if not VOLUME_POPUP.is_file():
        raise PatchError(f"VolumePopup not found: {VOLUME_POPUP}")
    original = VOLUME_POPUP.read_text(encoding="utf-8")
    patched = patch_volume_popup(original)
    if patched == original:
        validate_qml(VOLUME_POPUP)
        return False

    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{VOLUME_POPUP.name}.", dir=VOLUME_POPUP.parent, text=True
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(patched)
        os.chmod(temporary, VOLUME_POPUP.stat().st_mode)
        validate_qml(temporary)
        backup(VOLUME_POPUP)
        os.replace(temporary, VOLUME_POPUP)
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
    if not shutil.which("qmllint"):
        raise PatchError("missing required command: qmllint")
    if not (ADDON_DIR / "loopback.py").is_file():
        raise PatchError("loopback controller is missing")

    changes = []
    if install_component():
        changes.append("Streams control")
    if patch_popup():
        changes.append("audio panel")
    if changes:
        reload_quickshell()
        print("headset-mic-loopback: updated " + ", ".join(changes))
    else:
        print("headset-mic-loopback: addon already installed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"headset-mic-loopback: {error}; no further changes applied", file=sys.stderr)
        raise SystemExit(1)
