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
TOPBAR = Path(os.environ.get("MUSIC_PREVIEW_TOPBAR", QS_DIR / "TopBar.qml")).expanduser()
SHELL_QML = QS_DIR / "Shell.qml"
ADDON_DIR = XDG_DATA_HOME / "quickshell-addons/music-preview-rounded"
BACKUP_DIR = ADDON_DIR / "backups"

IMPORT_BEGIN = "// BEGIN user-addon: music-preview-rounded import"
IMPORT_END = "// END user-addon: music-preview-rounded import"
ART_BEGIN = "// BEGIN user-addon: music-preview-rounded art"
ART_END = "// END user-addon: music-preview-rounded art"


class PatchError(RuntimeError):
    pass


def find_matching_brace(text: str, opening: int) -> int:
    depth = 0
    quote = ""
    escaped = False
    index = opening
    while index < len(text):
        char = text[index]
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
        elif char in ('"', "'"):
            quote = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
        index += 1
    raise PatchError("unbalanced TopBar QML braces")


def patch_topbar(text: str) -> str:
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
    if image_start < 0:
        raise PatchError("music preview Image block not found")
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


def validate_qml(path: Path) -> None:
    result = subprocess.run(["qmllint", str(path)], capture_output=True, text=True)
    if result.returncode:
        raise PatchError((result.stdout + result.stderr).strip())


def backup(path: Path) -> None:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    shutil.copy2(path, BACKUP_DIR / f"{path.name}.{stamp}")


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
    if not TOPBAR.is_file():
        raise PatchError(f"TopBar.qml not found: {TOPBAR}")
    if not shutil.which("qmllint"):
        raise PatchError("missing required command: qmllint")
    original = TOPBAR.read_text(encoding="utf-8")
    patched = patch_topbar(original)
    if patched == original:
        validate_qml(TOPBAR)
        print("music-preview-rounded: addon already installed")
        return 0

    descriptor, temporary_name = tempfile.mkstemp(prefix=".TopBar.qml.", dir=TOPBAR.parent, text=True)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(patched)
        os.chmod(temporary, TOPBAR.stat().st_mode)
        validate_qml(temporary)
        backup(TOPBAR)
        os.replace(temporary, TOPBAR)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise
    reload_quickshell()
    print("music-preview-rounded: rounded top bar album art")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"music-preview-rounded: {error}; TopBar was not changed", file=os.sys.stderr)
        raise SystemExit(1)
