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
HYPR_BASE = Path(
    os.environ.get(
        "HYPR_CONFIG_DIR",
        f"{os.environ.get('XDG_CONFIG_HOME', str(HOME / '.config'))}/hypr",
    )
).expanduser()
QS_DIR = Path(
    os.environ.get("HYPR_QUICKSHELL_DIR", HYPR_BASE / "scripts/quickshell")
).expanduser()
ADDON_DIR = (
    Path(os.environ.get("XDG_DATA_HOME", str(HOME / ".local/share"))).expanduser()
    / "quickshell-addons/loading-icon"
)
BACKUP_DIR = ADDON_DIR / "backups"

TARGETS = {
    "wallpaper": QS_DIR / "wallpaper/WallpaperPicker.qml",
    "updater": QS_DIR / "updater/UpdaterPopup.qml",
    "movies": QS_DIR / "movies/MovieWidget.qml",
    "network": QS_DIR / "network/NetworkPopup.qml",
}


class PatchError(RuntimeError):
    pass


WALLPAPER_LOADER = """                    // BEGIN user-addon: shared-loading-icon wallpaper
                    Image {
                        id: notifSpinner
                        width: window.s(18)
                        height: window.s(18)
                        anchors.centerIn: parent
                        source: Qt.resolvedUrl("../loading-svgrepo-com.svg")
                        sourceSize: Qt.size(64, 64)
                        fillMode: Image.PreserveAspectFit
                        smooth: true

                        RotationAnimation on rotation {
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 1050
                            running: window.showSpinner && window.showNotification
                        }
                    }
                    // END user-addon: shared-loading-icon wallpaper"""

UPDATER_LOADER = """                        // BEGIN user-addon: shared-loading-icon updater
                        Image {
                            anchors.centerIn: parent
                            width: window.s(42)
                            height: window.s(42)
                            source: Qt.resolvedUrl("../loading-svgrepo-com.svg")
                            sourceSize: Qt.size(96, 96)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            transformOrigin: Item.Center

                            RotationAnimation on rotation {
                                from: 0
                                to: 360
                                duration: 1500
                                loops: Animation.Infinite
                                running: parent.visible
                            }
                        }
                        // END user-addon: shared-loading-icon updater"""

MOVIES_MAIN_LOADER = """                        // BEGIN user-addon: shared-loading-icon movies-main
                        Image {
                            Layout.alignment: Qt.AlignHCenter
                            width: window.s(34)
                            height: window.s(34)
                            source: Qt.resolvedUrl("../loading-svgrepo-com.svg")
                            sourceSize: Qt.size(96, 96)
                            fillMode: Image.PreserveAspectFit
                            smooth: true

                            RotationAnimation on rotation {
                                from: 0
                                to: 360
                                duration: 1050
                                loops: Animation.Infinite
                                running: parent.parent.visible
                            }
                        }
                        // END user-addon: shared-loading-icon movies-main"""

MOVIES_SERIES_LOADER = """                        // BEGIN user-addon: shared-loading-icon movies-series
                        Column {
                            anchors.centerIn: parent
                            visible: window.isLoadingSeries
                            spacing: window.s(10)

                            Image {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: window.s(28)
                                height: window.s(28)
                                source: Qt.resolvedUrl("../loading-svgrepo-com.svg")
                                sourceSize: Qt.size(64, 64)
                                fillMode: Image.PreserveAspectFit
                                smooth: true

                                RotationAnimation on rotation {
                                    from: 0
                                    to: 360
                                    duration: 1050
                                    loops: Animation.Infinite
                                    running: parent.visible
                                }
                            }

                            Text {
                                text: "Fetching episodes..."
                                color: window.subtext0
                                font.family: "JetBrains Mono"
                                font.pixelSize: window.s(13)
                            }
                        }
                        // END user-addon: shared-loading-icon movies-series"""

MOVIES_SOURCE_LOADER = """                                    // BEGIN user-addon: shared-loading-icon movies-source
                                    Image {
                                        anchors.fill: parent
                                        visible: model.status === "checking"
                                        source: Qt.resolvedUrl("../loading-svgrepo-com.svg")
                                        sourceSize: Qt.size(64, 64)
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true

                                        RotationAnimation on rotation {
                                            from: 0
                                            to: 360
                                            duration: 1050
                                            loops: Animation.Infinite
                                            running: model.status === "checking"
                                        }
                                    }
                                    // END user-addon: shared-loading-icon movies-source"""

NETWORK_LOADING_DOTS = """    // BEGIN user-addon: shared-loading-icon network-tasks
    component LoadingDots : Item {
        implicitWidth: window.s(20)
        implicitHeight: window.s(20)
        property color dotCol: window.text

        Image {
            anchors.fill: parent
            source: Qt.resolvedUrl("../loading-svgrepo-com.svg")
            sourceSize: Qt.size(64, 64)
            fillMode: Image.PreserveAspectFit
            smooth: true

            RotationAnimation on rotation {
                from: 0
                to: 360
                duration: 1050
                loops: Animation.Infinite
                running: parent.visible
            }
        }
    }
    // END user-addon: shared-loading-icon network-tasks"""

NETWORK_POWER_LOADER = """                    // BEGIN user-addon: shared-loading-icon network-power
                    Item {
                        id: pwrIcon
                        anchors.centerIn: parent
                        width: window.currentPower ? window.s(22) : window.s(64)
                        height: width

                        Behavior on width {
                            enabled: window.powerAnimAllowed
                            NumberAnimation { duration: 800; easing.type: Easing.InOutQuint }
                        }

                        Image {
                            anchors.fill: parent
                            visible: window.currentPowerPending
                            source: Qt.resolvedUrl("../loading-svgrepo-com.svg")
                            sourceSize: Qt.size(96, 96)
                            fillMode: Image.PreserveAspectFit
                            smooth: true

                            RotationAnimation on rotation {
                                from: 0
                                to: 360
                                duration: 1050
                                loops: Animation.Infinite
                                running: window.currentPowerPending
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !window.currentPowerPending
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: parent.width
                            color: window.currentPower ? window.crust : window.text
                            text: ""
                            Behavior on color {
                                enabled: window.powerAnimAllowed
                                ColorAnimation { duration: 800; easing.type: Easing.InOutQuint }
                            }
                        }
                    }
                    // END user-addon: shared-loading-icon network-power"""


def find_object_start(text: str, token_position: int, declaration: str) -> int:
    start = text.rfind(declaration, 0, token_position + len(declaration))
    if start == -1:
        raise PatchError(f"could not locate object '{declaration}' for loader")
    return start


def find_object_end(text: str, start: int) -> int:
    opening = text.find("{", start)
    if opening == -1:
        raise PatchError("loader object has no opening brace")
    depth = 0
    quote = ""
    escaped = False
    for index in range(opening, len(text)):
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
                return index + 1
    raise PatchError("loader object has no closing brace")


def replace_loader(
    text: str,
    marker: str,
    token: str,
    declaration: str,
    replacement: str,
) -> str:
    begin_marker = f"// BEGIN user-addon: shared-loading-icon {marker}"
    end_marker = f"// END user-addon: shared-loading-icon {marker}"
    begin = text.find(begin_marker)
    if begin != -1:
        begin = text.rfind("\n", 0, begin) + 1
        end = text.find(end_marker, begin)
        if end == -1:
            raise PatchError(f"missing end marker for {marker}")
        end = text.find("\n", end)
        if end == -1:
            end = len(text)
        return text[:begin] + replacement + text[end:]

    token_position = text.find(token)
    if token_position == -1:
        raise PatchError(f"loader anchor not found for {marker}")
    start = find_object_start(text, token_position, declaration)
    end = find_object_end(text, start)
    return text[:start] + replacement + text[end:]


def patch_wallpaper(text: str) -> str:
    return replace_loader(
        text, "wallpaper", "id: notifSpinner", "Canvas {", WALLPAPER_LOADER
    )


def patch_updater(text: str) -> str:
    return replace_loader(text, "updater", 'text: "󰑮"', "Text {", UPDATER_LOADER)


def patch_movies(text: str) -> str:
    text = replace_loader(
        text,
        "movies-main",
        "property real spinAngle: 0",
        "Item {",
        MOVIES_MAIN_LOADER,
    )
    text = replace_loader(
        text,
        "movies-series",
        'text: "Fetching episodes..."',
        "Text {",
        MOVIES_SERIES_LOADER,
    )
    return replace_loader(
        text,
        "movies-source",
        "property real spinAngle: 0",
        "Item {",
        MOVIES_SOURCE_LOADER,
    )


def patch_network(text: str) -> str:
    text = replace_loader(
        text,
        "network-tasks",
        "component LoadingDots : Row",
        "component LoadingDots : Row {",
        NETWORK_LOADING_DOTS,
    )
    return replace_loader(
        text,
        "network-power",
        'text: window.currentPowerPending ? "󰑮" : ""',
        "Text {",
        NETWORK_POWER_LOADER,
    )


PATCHERS = {
    "wallpaper": patch_wallpaper,
    "updater": patch_updater,
    "movies": patch_movies,
    "network": patch_network,
}


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
    fd, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.loading-icon.",
        dir=path.parent,
        text=True,
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
        temporary.chmod(path.stat().st_mode)
        os.replace(temporary, path)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def install_asset() -> bool:
    source = ADDON_DIR / "loading-svgrepo-com.svg"
    target = QS_DIR / source.name
    if not source.is_file():
        raise PatchError(f"missing shared loader asset: {source}")
    if target.is_file() and target.read_bytes() == source.read_bytes():
        return False
    temporary = target.with_name(f".{target.name}.loading-icon")
    shutil.copy2(source, temporary)
    os.replace(temporary, target)
    return True


def backup(path: Path) -> None:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    shutil.copy2(path, BACKUP_DIR / f"{path.name}.{timestamp}")


def main() -> int:
    missing = [str(path) for path in TARGETS.values() if not path.is_file()]
    if missing:
        raise PatchError("active QML file not found: " + ", ".join(missing))

    asset_changed = install_asset()
    changed: list[str] = []

    for name, path in TARGETS.items():
        original = path.read_text(encoding="utf-8")
        patched = PATCHERS[name](original)
        if patched == original:
            validate_qml(path)
            continue

        preview = path.with_name(f".{path.name}.loading-icon-preview.qml")
        preview.write_text(patched, encoding="utf-8")
        try:
            validate_qml(preview)
        finally:
            preview.unlink(missing_ok=True)

        backup(path)
        atomic_write(path, patched)
        changed.append(name)

    status = changed[:]
    if asset_changed:
        status.append("asset")
    if status:
        print("loading-icon: updated " + ", ".join(status))
    else:
        print("loading-icon: addon already installed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"loading-icon: {error}; no additional file changed", file=sys.stderr)
        raise SystemExit(1)
