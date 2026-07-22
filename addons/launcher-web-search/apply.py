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
QS_DIR = Path(
    os.environ.get("HYPR_QUICKSHELL_DIR", HYPR_BASE / "scripts/quickshell")
).expanduser()
LAUNCHER = Path(
    os.environ.get(
        "LAUNCHER_WEB_SEARCH_QML",
        QS_DIR / "applauncher/appLauncher.qml",
    )
).expanduser()
SHELL_QML = QS_DIR / "Shell.qml"
ADDON_DIR = XDG_DATA_HOME / "quickshell-addons/launcher-web-search"
BACKUP_DIR = ADDON_DIR / "backups"

SEARCH_FUNCTION_BLOCK = """    // BEGIN user-addon: launcher-web-search function
    function searchWeb(query) {
        let term = String(query).trim();
        if (term.length === 0) return;

        let searchUrl = "https://www.google.com/search?q=" + encodeURIComponent(term);
        Quickshell.execDetached(["zen-browser", "--new-tab", searchUrl]);
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
    }
    // END user-addon: launcher-web-search function
"""


class PatchError(RuntimeError):
    pass


def find_matching_brace(text: str, opening: int) -> int:
    depth = 0
    quote = ""
    escaped = False
    for index in range(opening, len(text)):
        character = text[index]
        if quote:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == quote:
                quote = ""
            continue
        if character in ('"', "'"):
            quote = character
        elif character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return index
    raise PatchError("unterminated QML block")


def patch_launcher(text: str) -> str:
    text = re.sub(
        r"^[ \t]*// BEGIN user-addon: launcher-web-search function\n"
        r".*?"
        r"^[ \t]*// END user-addon: launcher-web-search function\n?",
        "",
        text,
        count=1,
        flags=re.DOTALL | re.MULTILINE,
    )
    text = re.sub(
        r"^[ \t]*// BEGIN user-addon: launcher-web-search tab-handler\n"
        r".*?"
        r"^[ \t]*// END user-addon: launcher-web-search tab-handler\n?",
        "",
        text,
        count=1,
        flags=re.DOTALL | re.MULTILINE,
    )

    launch_function = re.search(r"^\s*function\s+launchApp\s*\([^)]*\)\s*\{", text, re.MULTILINE)
    if not launch_function:
        raise PatchError("launchApp function anchor not found")
    opening = text.find("{", launch_function.start())
    closing = find_matching_brace(text, opening)
    suffix = text[closing + 1 :].lstrip("\n")
    text = text[: closing + 1] + "\n\n" + SEARCH_FUNCTION_BLOCK + "\n" + suffix

    return_handler = re.search(r"^(\s*)Keys\.onReturnPressed:\s*\{", text, re.MULTILINE)
    if not return_handler:
        raise PatchError("Return key handler anchor not found")
    indentation = return_handler.group(1)
    nested = indentation + "    "
    tab_block = (
        f"{indentation}// BEGIN user-addon: launcher-web-search tab-handler\n"
        f"{indentation}Keys.onTabPressed: {{\n"
        f"{nested}searchWeb(searchInput.text);\n"
        f"{nested}event.accepted = true;\n"
        f"{indentation}}}\n"
        f"{indentation}// END user-addon: launcher-web-search tab-handler\n"
    )
    text = text[: return_handler.start()] + tab_block + text[return_handler.start() :]

    placeholder = re.compile(r'^(\s*)placeholderText:\s*.*$', re.MULTILINE)
    if not placeholder.search(text):
        raise PatchError("search placeholder anchor not found")
    text = placeholder.sub(
        r'\1placeholderText: "Search apps..."',
        text,
        count=1,
    )
    return text


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.stem}.", suffix=".qml", dir=path.parent, text=True
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
    if not LAUNCHER.is_file():
        raise PatchError(f"app launcher not found: {LAUNCHER}")
    if not shutil.which("zen-browser"):
        raise PatchError("zen-browser command not found")

    original = LAUNCHER.read_text(encoding="utf-8")
    patched = patch_launcher(original)
    if patched == original:
        print("launcher-web-search: addon already installed")
        return 0

    backup(LAUNCHER)
    atomic_write(LAUNCHER, patched)
    suffix = " and reloaded Quickshell" if reload_quickshell() else ""
    print("launcher-web-search: enabled Tab search in Zen" + suffix)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"launcher-web-search: {error}; no launcher changed", file=sys.stderr)
        raise SystemExit(1)
