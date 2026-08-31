#!/usr/bin/env python3

from __future__ import annotations

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
QS_DIR = Path(os.environ.get("HYPR_QUICKSHELL_DIR", HYPR_BASE / "scripts/quickshell")).expanduser()
FLOATING_QML = Path(os.environ.get("DRAWING_NOTES_FLOATING_QML", QS_DIR / "Floating.qml")).expanduser()
QUICKACTIONS_DIR = QS_DIR / "quickactions"
ADDON_DIR = XDG_DATA_HOME / "quickshell-addons/drawing-notes"
SOURCE = ADDON_DIR / "DrawingNotesAction.qml"
TARGET = QUICKACTIONS_DIR / "DrawingNotesAction.qml"
SHELL_QML = QS_DIR / "Shell.qml"
BACKUP_DIR = ADDON_DIR / "backups"
NOTE_PATH = Path(
    os.environ.get("QS_MARKDOWN_NOTES_FILE", HOME / "Documents/Notes/quick-notes.md")
).expanduser()

DRAW_MODULE = '"quickactions/DrawAction.qml"'
NOTES_MODULE = '"quickactions/DrawingNotesAction.qml"'


class PatchError(RuntimeError):
    pass


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


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.stem}.", suffix=path.suffix, dir=path.parent, text=True
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
        validate_qml(temporary)
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
    if not FLOATING_QML.is_file():
        raise PatchError(f"floating widget not found: {FLOATING_QML}")
    if not SOURCE.is_file():
        raise PatchError(f"addon asset not found: {SOURCE}")
    if not (QUICKACTIONS_DIR / "DrawAction.qml").is_file():
        raise PatchError("DrawAction.qml was not found")

    validate_qml(SOURCE)
    source_text = SOURCE.read_text(encoding="utf-8")
    target_changed = not TARGET.is_file() or TARGET.read_text(encoding="utf-8") != source_text
    if target_changed:
        atomic_write(TARGET, source_text)

    original = FLOATING_QML.read_text(encoding="utf-8")
    if NOTES_MODULE in original:
        patched = original
    elif DRAW_MODULE in original:
        patched = original.replace(DRAW_MODULE, NOTES_MODULE, 1)
    else:
        raise PatchError("DrawAction module anchor not found in Floating.qml")

    floating_changed = patched != original
    if floating_changed:
        backup(FLOATING_QML)
        atomic_write(FLOATING_QML, patched)

    NOTE_PATH.parent.mkdir(parents=True, exist_ok=True)
    NOTE_PATH.touch(exist_ok=True)

    if not target_changed and not floating_changed:
        print(f"drawing-notes: addon already installed; notes at {NOTE_PATH}")
        return 0

    suffix = " and reloaded Quickshell" if reload_quickshell() else ""
    print(f"drawing-notes: enabled drawing/Markdown toggle{suffix}; notes at {NOTE_PATH}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"drawing-notes: {error}; no floating widget changed", file=sys.stderr)
        raise SystemExit(1)
