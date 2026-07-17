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
HYPR_BASE = Path(
    os.environ.get("HYPR_CONFIG_DIR", f"{os.environ.get('XDG_CONFIG_HOME', str(HOME / '.config'))}/hypr")
).expanduser()
PICKER = Path(
    os.environ.get(
        "WALLPAPER_RANDOM_PICKER",
        HYPR_BASE / "scripts/quickshell/wallpaper/WallpaperPicker.qml",
    )
).expanduser()
MANAGER = Path(
    os.environ.get(
        "WALLPAPER_RANDOM_MANAGER",
        HYPR_BASE / "scripts/qs_manager.sh",
    )
).expanduser()
ADDON_DIR = Path(
    os.environ.get("XDG_DATA_HOME", str(HOME / ".local/share"))
).expanduser() / "quickshell-addons/wallpaper-random"
BACKUP_DIR = ADDON_DIR / "backups"
INSTALL_DIR = PICKER.parent

IMPORT_BLOCK = """// BEGIN user-addon: wallpaper-random import
import "." as WallpaperRandom
// END user-addon: wallpaper-random import
"""

STATE_BLOCK = """    // BEGIN user-addon: wallpaper-random state
    property bool randomWallpaperActive: false
    property string lastRandomWallName: ""
    property int randomScrollTargetIndex: -1
    property int randomScrollDirection: 0
    readonly property bool isRandomScrolling: randomScrollTimer.running || randomScrollSettleTimer.running

    function scrollToRandomWallpaper(targetIndex, fileName, isVideo) {
        randomScrollTimer.stop();
        randomScrollSettleTimer.stop();
        window.currentFilter = "All";

        Qt.callLater(() => {
            view.forceLayout();

            let startIndex = Math.max(0, view.currentIndex);
            window.randomScrollTargetIndex = targetIndex;
            window.randomScrollDirection = targetIndex >= startIndex ? 1 : -1;

            if (startIndex === targetIndex) {
                randomScrollSettleTimer.restart();
            } else {
                randomScrollTimer.start();
            }
            view.forceActiveFocus();
            window.applyWallpaper(fileName, isVideo, true, true);
        });
    }

    Timer {
        id: randomScrollTimer
        interval: 30
        repeat: true
        onTriggered: {
            let nextIndex = view.currentIndex + window.randomScrollDirection;
            let reachedTarget = window.randomScrollDirection > 0
                ? nextIndex >= window.randomScrollTargetIndex
                : nextIndex <= window.randomScrollTargetIndex;

            view.currentIndex = reachedTarget ? window.randomScrollTargetIndex : nextIndex;

            if (reachedTarget) {
                stop();
                randomScrollSettleTimer.restart();
            }
        }
    }

    Timer {
        id: randomScrollSettleTimer
        interval: 120
        onTriggered: {
            view.currentIndex = window.randomScrollTargetIndex;
            view.forceLayout();
            view.positionViewAtIndex(window.randomScrollTargetIndex, ListView.Center);
        }
    }

    function applyRandomWallpaper() {
        if (window.isApplying || localProxyModel.count === 0) return;
        if (window.getMonitorOutputs() === "none") return;

        let excludedName = window.lastRandomWallName !== ""
            ? window.lastRandomWallName
            : window.targetWallName;
        let randomIndex = Math.floor(Math.random() * localProxyModel.count);

        if (localProxyModel.count > 1) {
            for (let i = 0; i < localProxyModel.count; i++) {
                let candidateIndex = (randomIndex + i) % localProxyModel.count;
                let candidateName = String(localProxyModel.get(candidateIndex).fileName || "");
                if (candidateName !== "" && window.getCleanName(candidateName) !== window.getCleanName(excludedName)) {
                    randomIndex = candidateIndex;
                    break;
                }
            }
        }

        let fileName = String(localProxyModel.get(randomIndex).fileName || "");
        if (fileName === "") return;

        window.randomWallpaperActive = true;
        window.lastRandomWallName = fileName;
        window.scrollToRandomWallpaper(randomIndex, fileName, fileName.startsWith("000_"));
    }
    // END user-addon: wallpaper-random state
"""

RESET_BLOCK = """        // BEGIN user-addon: wallpaper-random manual reset
        if (keepRandomHighlight !== true) {
            window.randomWallpaperActive = false;
            window.lastRandomWallName = "";
        }
        // END user-addon: wallpaper-random manual reset

"""

BUTTON_BLOCK = """            // BEGIN user-addon: wallpaper-random button
            WallpaperRandom.RandomWallpaperButton {
                uiScale: window.s(1)
                active: window.randomWallpaperActive
                available: localProxyModel.count > 0 && !window.isApplying
                textColor: _theme.text
                surface1Color: _theme.surface1
                surface2Color: _theme.surface2
                onTriggered: window.applyRandomWallpaper()
            }
            // END user-addon: wallpaper-random button

"""

MANAGER_BLOCK = r'''        # BEGIN user-addon: wallpaper-current-selection
        CURRENT_SRC=""
        if pgrep -a "mpvpaper" > /dev/null; then
            CURRENT_SRC=$(pgrep -a mpvpaper \
                | sed -n "s#.* \($SRC_DIR/.*\)$#\1#p" \
                | head -n1)
        elif command -v awww >/dev/null; then
            CURRENT_SRC=$(awww query 2>/dev/null \
                | sed -n 's#^.*currently displaying: image: ##p' \
                | grep -F "$SRC_DIR/" \
                | head -n1)
        fi
        # END user-addon: wallpaper-current-selection
'''


class PatchError(RuntimeError):
    pass


def insert_once(text: str, marker: str, anchor_pattern: str, block: str, after: bool) -> str:
    if marker in text:
        return text

    match = re.search(anchor_pattern, text, flags=re.MULTILINE)
    if not match:
        raise PatchError(f"required QML anchor not found: {anchor_pattern}")

    position = match.end() if after else match.start()
    return text[:position] + ("\n" if after else "") + block + text[position:]


def patch_picker(text: str) -> str:
    text = re.sub(
        r"// BEGIN user-addon: wallpaper-random import\n"
        r'import "\.\./\.\./\.\./user-addons/wallpaper-random" as WallpaperRandom\n'
        r"// END user-addon: wallpaper-random import\n",
        "",
        text,
        count=1,
    )
    text = re.sub(
        r"^(\s*)(?:WallpaperRandom\.)*RandomWallpaperButton \{",
        r"\1WallpaperRandom.RandomWallpaperButton {",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r"\s*// BEGIN user-addon: wallpaper-random state\n"
        r".*?"
        r"// END user-addon: wallpaper-random state\n",
        "\n",
        text,
        count=1,
        flags=re.DOTALL,
    )
    text = re.sub(
        r"\s*// BEGIN user-addon: wallpaper-random button\n"
        r".*?"
        r"// END user-addon: wallpaper-random button\n",
        "\n",
        text,
        count=1,
        flags=re.DOTALL,
    )
    text = insert_once(
        text,
        "BEGIN user-addon: wallpaper-random import",
        r'^import "\.\./"\s*$',
        IMPORT_BLOCK,
        after=True,
    )
    text = insert_once(
        text,
        "BEGIN user-addon: wallpaper-random state",
        r"^\s*property bool isMonitorSelectorOpen: false\s*$",
        STATE_BLOCK,
        after=True,
    )

    signature = re.compile(
        r"function applyWallpaper\("
        r"safeFileName,\s*isVideo"
        r"(?:,\s*keepRandomHighlight)?"
        r"(?:,\s*forceLocal)?"
        r"\)"
    )
    if not signature.search(text):
        raise PatchError("applyWallpaper function signature not found")
    text = signature.sub(
        "function applyWallpaper(safeFileName, isVideo, keepRandomHighlight, forceLocal)",
        text,
        count=1,
    )

    search_branch = re.compile(
        r'if \((?:!forceLocal && )?window\.currentFilter === "Search" && window\.hasSearched\)'
    )
    if not search_branch.search(text):
        raise PatchError("online search apply branch not found")
    text = search_branch.sub(
        'if (!forceLocal && window.currentFilter === "Search" && window.hasSearched)',
        text,
        count=1,
    )

    highlight_duration = re.compile(
        r"highlightMoveDuration:\s*(?:window\.isRandomScrolling\s*\?\s*(?:140|85)\s*:\s*)?"
        r"\(?window\.initialFocusSet\s*\?\s*500\s*:\s*0\)?"
    )
    if not highlight_duration.search(text):
        raise PatchError("ListView highlight duration binding not found")
    text = highlight_duration.sub(
        "highlightMoveDuration: window.isRandomScrolling ? 85 : (window.initialFocusSet ? 500 : 0)",
        text,
        count=1,
    )

    text = insert_once(
        text,
        "BEGIN user-addon: wallpaper-random manual reset",
        r'^\s*if \(outputs === "none"\) return;\s*$',
        RESET_BLOCK,
        after=True,
    )
    text = insert_once(
        text,
        "BEGIN user-addon: wallpaper-random button",
        r"^\s*Rectangle \{\s*\n\s*id: searchBox\s*$",
        BUTTON_BLOCK,
        after=False,
    )
    text = re.sub(
        r"(// END user-addon: wallpaper-random button)\n+(\s*Rectangle \{\n\s*id: searchBox)",
        r"\1\n\n\2",
        text,
        count=1,
    )
    return text


def patch_manager(text: str) -> str:
    marked_block = re.compile(
        r"^\s*# BEGIN user-addon: wallpaper-current-selection\n"
        r".*?"
        r"^\s*# END user-addon: wallpaper-current-selection\n",
        flags=re.MULTILINE | re.DOTALL,
    )
    if marked_block.search(text):
        return marked_block.sub(lambda _: MANAGER_BLOCK, text, count=1)

    upstream_block = re.compile(
        r'^\s*CURRENT_SRC=""\n'
        r'^\s*if pgrep -a "mpvpaper" > /dev/null; then\n'
        r'.*?'
        r'^\s*fi\n'
        r'(?=\n\s*TARGET_THUMB="")',
        flags=re.MULTILINE | re.DOTALL,
    )
    if not upstream_block.search(text):
        raise PatchError("current wallpaper detection block not found in qs_manager.sh")
    return upstream_block.sub(lambda _: MANAGER_BLOCK.rstrip("\n"), text, count=1)


def validate(path: Path) -> None:
    qmllint = shutil.which("qmllint")
    if qmllint is None:
        raise PatchError("qmllint is required but was not found")

    result = subprocess.run(
        [
            qmllint,
            "-I",
            str(HOME / ".config/hypr/scripts/quickshell"),
            str(path),
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        details = (result.stdout + result.stderr).strip()
        raise PatchError(f"qmllint rejected the patched file:\n{details}")


def validate_shell(path: Path) -> None:
    result = subprocess.run(
        ["bash", "-n", str(path)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        details = (result.stdout + result.stderr).strip()
        raise PatchError(f"bash rejected the patched qs_manager.sh:\n{details}")


def write_temporary(target: Path, content: str, prefix: str) -> Path:
    fd, temporary_name = tempfile.mkstemp(prefix=prefix, dir=target.parent, text=True)
    temporary = Path(temporary_name)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(content)
    os.chmod(temporary, target.stat().st_mode)
    return temporary


def install_assets() -> bool:
    changed = False
    for name in ("RandomWallpaperButton.qml", "random.svg"):
        source = ADDON_DIR / name
        target = INSTALL_DIR / name
        if not source.is_file():
            raise PatchError(f"addon asset not found: {source}")
        if target.is_file() and target.read_bytes() == source.read_bytes():
            continue

        temporary = target.with_name(f".{target.name}.wallpaper-random")
        shutil.copy2(source, temporary)
        os.replace(temporary, target)
        changed = True
    return changed


def main() -> int:
    if not PICKER.is_file():
        print(f"wallpaper-random: picker not found: {PICKER}", file=sys.stderr)
        return 1
    if not MANAGER.is_file():
        print(f"wallpaper-random: manager not found: {MANAGER}", file=sys.stderr)
        return 1

    original = PICKER.read_text(encoding="utf-8")
    manager_original = MANAGER.read_text(encoding="utf-8")
    try:
        patched = patch_picker(original)
        manager_patched = patch_manager(manager_original)
    except PatchError as error:
        print(f"wallpaper-random: {error}; no file changed", file=sys.stderr)
        return 1

    validate(ADDON_DIR / "RandomWallpaperButton.qml")
    assets_changed = install_assets()

    if patched == original and manager_patched == manager_original:
        validate(PICKER)
        validate_shell(MANAGER)
        status = "assets refreshed" if assets_changed else "addon already installed"
        print(f"wallpaper-random: {status}")
        return 0

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    backup = BACKUP_DIR / f"WallpaperPicker.qml.{timestamp}"
    manager_backup = BACKUP_DIR / f"qs_manager.sh.{timestamp}"
    backups = []
    temporary = write_temporary(PICKER, patched, ".WallpaperPicker.qml.")
    manager_temporary = write_temporary(MANAGER, manager_patched, ".qs_manager.sh.")
    try:
        validate(temporary)
        validate_shell(manager_temporary)
        if patched != original:
            shutil.copy2(PICKER, backup)
            backups.append(backup)
            os.replace(temporary, PICKER)
        else:
            temporary.unlink()
        if manager_patched != manager_original:
            shutil.copy2(MANAGER, manager_backup)
            backups.append(manager_backup)
            os.replace(manager_temporary, MANAGER)
        else:
            manager_temporary.unlink()
    except Exception:
        temporary.unlink(missing_ok=True)
        manager_temporary.unlink(missing_ok=True)
        raise

    print(f"wallpaper-random: addon installed; backups: {', '.join(map(str, backups))}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"wallpaper-random: {error}; no file changed", file=sys.stderr)
        raise SystemExit(1)
