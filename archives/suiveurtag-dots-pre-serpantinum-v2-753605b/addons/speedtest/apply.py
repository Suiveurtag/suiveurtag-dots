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
    os.environ.get("HYPR_CONFIG_DIR", f"{os.environ.get('XDG_CONFIG_HOME', str(HOME / '.config'))}/hypr")
).expanduser()
ADDON_DIR = Path(
    os.environ.get("XDG_DATA_HOME", str(HOME / ".local/share"))
).expanduser() / "quickshell-addons/speedtest"
QS_DIR = Path(
    os.environ.get("HYPR_QUICKSHELL_DIR", HYPR_BASE / "scripts/quickshell")
).expanduser()
NETWORK_POPUP = QS_DIR / "network/NetworkPopup.qml"
NETWORK_DIR = NETWORK_POPUP.parent
BACKUP_DIR = ADDON_DIR / "backups"

IMPORT_BLOCK = """// BEGIN user-addon: speedtest import
import "." as SpeedtestComponents
// END user-addon: speedtest import
"""

STATE_BLOCK = """    // BEGIN user-addon: speedtest state
    property bool showSpeedtestPanel: false
    property string speedtestState: "idle"
    property string speedtestPhase: "idle"
    property real speedtestProgress: 0.0
    property real speedtestVisualMbps: 0.0
    property string speedtestLive: "0"
    property string speedtestDownload: ""
    property string speedtestUpload: ""
    property string speedtestLatency: ""
    property string speedtestServer: ""
    property string speedtestSummary: ""
    property string speedtestMessage: ""
    readonly property bool speedtestRunning: window.speedtestState === "running"
    readonly property string speedtestStatusFile: window.cacheDir + "/native-speedtest.json"

    Behavior on speedtestProgress {
        NumberAnimation { duration: 700; easing.type: Easing.OutQuint }
    }
    Behavior on speedtestVisualMbps {
        NumberAnimation { duration: 920; easing.type: Easing.OutQuint }
    }

    function speedtestShellQuote(value) {
        let safe = String(value === undefined || value === null ? "" : value);
        return "'" + safe.replace(/'/g, "'\\\\''") + "'";
    }

    function runNativeSpeedtest() {
        if (nativeSpeedtestProcess.running) return;
        window.showSpeedtestPanel = true;
        window.speedtestState = "running";
        window.speedtestPhase = "latency";
        window.speedtestProgress = 0.01;
        window.speedtestVisualMbps = 0;
        window.speedtestLive = "0";
        window.speedtestDownload = "";
        window.speedtestUpload = "";
        window.speedtestLatency = "";
        window.speedtestServer = "Cloudflare";
        window.speedtestSummary = "";
        window.speedtestMessage = "Preparing latency samples";
        Quickshell.execDetached(["bash", "-c", "rm -f " + window.speedtestShellQuote(window.speedtestStatusFile)]);
        nativeSpeedtestProcess.running = true;
        speedtestStatusTimer.restart();
    }

    function processNativeSpeedtestJson(textData) {
        if (textData === "") return;
        try {
            let data = JSON.parse(textData);
            window.speedtestState = data.status || window.speedtestState;
            window.speedtestPhase = data.phase || window.speedtestPhase;
            if (data.progress !== undefined) {
                window.speedtestProgress = Math.max(0, Math.min(1, Number(data.progress)));
            }
            if (data.live_mbps !== undefined && data.live_mbps !== "") {
                window.speedtestLive = String(data.live_mbps);
                let visualValue = Number(data.live_mbps);
                if (!isNaN(visualValue)) window.speedtestVisualMbps = Math.max(0, visualValue);
            }
            if (data.download_mbps !== undefined) window.speedtestDownload = String(data.download_mbps);
            if (data.upload_mbps !== undefined) window.speedtestUpload = String(data.upload_mbps);
            if (data.latency_ms !== undefined) window.speedtestLatency = String(data.latency_ms);
            if (data.server) window.speedtestServer = data.server;
            if (data.summary !== undefined) window.speedtestSummary = String(data.summary);
            if (data.message !== undefined) window.speedtestMessage = String(data.message);
        } catch(e) {}
    }

    Process {
        id: nativeSpeedtestProcess
        command: ["bash", window.scriptsDir + "/native_speedtest.sh", window.speedtestStatusFile]
        stdout: StdioCollector {
            onStreamFinished: {
                processNativeSpeedtestJson(this.text.trim());
                if (window.speedtestState === "running") {
                    window.speedtestState = "error";
                    window.speedtestMessage = "Speedtest failed";
                }
            }
        }
    }

    Process {
        id: speedtestStatusReader
        command: ["bash", "-c", "cat " + window.speedtestShellQuote(window.speedtestStatusFile) + " 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: processNativeSpeedtestJson(this.text.trim())
        }
    }

    Timer {
        id: speedtestStatusTimer
        interval: 250
        running: window.showSpeedtestPanel && window.speedtestRunning
        repeat: true
        onTriggered: {
            if (!speedtestStatusReader.running) speedtestStatusReader.running = true;
        }
    }
    // END user-addon: speedtest state
"""

SPEEDTEST_PANEL_BLOCK = """            // BEGIN user-addon: speedtest panel
            Rectangle {
                id: speedtestPanel
                anchors.fill: parent
                anchors.margins: window.s(22)
                anchors.bottomMargin: window.s(96)
                radius: window.s(22)
                z: 85
                visible: opacity > 0.01
                opacity: window.showSpeedtestPanel ? 1.0 : 0.0
                color: Qt.rgba(window.base.r, window.base.g, window.base.b, 0.92)
                border.color: window.surface1
                border.width: 1
                clip: true
                Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                Rectangle {
                    width: parent.width * 0.72
                    height: width
                    radius: width / 2
                    anchors.centerIn: parent
                    opacity: 0.12
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.lighter(window.sapphire, 1.18) }
                        GradientStop { position: 1.0; color: Qt.lighter(window.mauve, 1.08) }
                    }
                }

                Canvas {
                    id: speedGauge
                    anchors.centerIn: parent
                    width: window.s(330)
                    height: width
                    property real progressValue: window.speedtestProgress
                    property string phaseValue: window.speedtestPhase
                    property real pulse: 0.0
                    onProgressValueChanged: requestPaint()
                    onPhaseValueChanged: requestPaint()
                    onPulseChanged: requestPaint()

                    NumberAnimation on pulse {
                        from: 0
                        to: Math.PI * 2
                        duration: 1800
                        loops: Animation.Infinite
                        running: window.showSpeedtestPanel && window.speedtestRunning
                    }

                    onPaint: {
                        let ctx = getContext("2d");
                        let s = window.s;
                        ctx.clearRect(0, 0, width, height);
                        let cx = width / 2;
                        let cy = height / 2;
                        let radius = Math.min(width, height) / 2 - s(16);
                        let start = Math.PI * 0.78;
                        let end = Math.PI * 2.22;
                        let p = Math.max(0, Math.min(1, progressValue));

                        ctx.lineCap = "round";
                        ctx.lineWidth = s(18);
                        ctx.beginPath();
                        ctx.arc(cx, cy, radius, start, end);
                        ctx.strokeStyle = window.surface0;
                        ctx.globalAlpha = 0.86;
                        ctx.stroke();

                        ctx.beginPath();
                        ctx.arc(cx, cy, radius, start, start + (end - start) * p);
                        ctx.strokeStyle = phaseValue === "upload" ? window.mauve : window.sapphire;
                        ctx.globalAlpha = 1.0;
                        ctx.stroke();

                        if (window.speedtestRunning) {
                            ctx.beginPath();
                            ctx.arc(cx, cy, radius - s(36) + Math.sin(pulse) * s(5), 0, Math.PI * 2);
                            ctx.strokeStyle = phaseValue === "upload" ? window.pink : window.blue;
                            ctx.lineWidth = s(2);
                            ctx.globalAlpha = 0.26;
                            ctx.stroke();
                        }
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: window.s(30)
                    spacing: window.s(14)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: window.s(14)

                        Rectangle {
                            width: window.s(46)
                            height: width
                            radius: width / 2
                            color: window.surface0
                            border.color: window.surface2
                            border.width: 1

                            Image {
                                anchors.centerIn: parent
                                width: window.s(26)
                                height: width
                                source: Qt.resolvedUrl("speed-alt-svgrepo-com.svg")
                                opacity: 0.9
                                smooth: true
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: window.s(2)
                            Text {
                                Layout.fillWidth: true
                                text: "Native Speedtest"
                                font.family: "JetBrains Mono"
                                font.weight: Font.Black
                                font.pixelSize: window.s(18)
                                color: window.text
                            }
                            Text {
                                Layout.fillWidth: true
                                text: window.speedtestRunning ? window.speedtestMessage : (window.speedtestState === "ok" ? window.speedtestSummary : (window.speedtestState === "error" ? window.speedtestMessage : "Cloudflare edge test"))
                                font.family: "JetBrains Mono"
                                font.pixelSize: window.s(11)
                                color: window.overlay0
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            width: window.s(36)
                            height: width
                            radius: width / 2
                            color: closeSpeedtestMa.containsMouse ? window.surface1 : "transparent"
                            border.color: window.surface1
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: window.s(16)
                                color: window.text
                                text: "󰅖"
                            }
                            MouseArea {
                                id: closeSpeedtestMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: window.showSpeedtestPanel = false
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: window.s(2)

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: window.speedtestRunning ? window.speedtestLive : (window.speedtestDownload !== "" ? window.speedtestDownload : "0")
                            font.family: "JetBrains Mono"
                            font.weight: Font.Black
                            font.pixelSize: window.s(56)
                            color: window.text
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: window.speedtestPhase === "upload" ? "Mbps upload" : (window.speedtestPhase === "complete" ? "Mbps download" : "Mbps download")
                            font.family: "JetBrains Mono"
                            font.weight: Font.Bold
                            font.pixelSize: window.s(13)
                            color: window.speedtestPhase === "upload" ? window.mauve : window.sapphire
                        }
                    }

                    Item { Layout.fillHeight: true }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: window.s(10)

                        Repeater {
                            model: [
                                { label: "Download", value: window.speedtestDownload !== "" ? window.speedtestDownload + " Mbps" : "--", color: window.sapphire },
                                { label: "Upload", value: window.speedtestUpload !== "" ? window.speedtestUpload + " Mbps" : "--", color: window.mauve },
                                { label: "Latency", value: window.speedtestLatency !== "" ? window.speedtestLatency + " ms" : "--", color: window.peach }
                            ]

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: window.s(76)
                                radius: window.s(14)
                                color: "#12ffffff"
                                border.color: modelData.color
                                border.width: 1
                                opacity: 0.96

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: window.s(12)
                                    spacing: window.s(4)
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: window.s(10)
                                        color: window.overlay0
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.value
                                        font.family: "JetBrains Mono"
                                        font.weight: Font.Black
                                        font.pixelSize: window.s(15)
                                        color: window.text
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: window.s(48)
                        radius: window.s(14)
                        color: speedtestStartMa.containsMouse ? Qt.lighter(window.activeColor, 1.12) : window.activeColor
                        opacity: window.speedtestRunning ? 0.55 : 1.0
                        Behavior on color { ColorAnimation { duration: 180 } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: window.s(8)
                            Text {
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: window.s(18)
                                color: window.crust
                                text: window.speedtestRunning ? "󰑮" : "󰓅"
                                RotationAnimation on rotation {
                                    from: 0; to: 360; duration: 850; loops: Animation.Infinite; running: window.speedtestRunning
                                }
                            }
                            Text {
                                font.family: "JetBrains Mono"
                                font.weight: Font.Black
                                font.pixelSize: window.s(13)
                                color: window.crust
                                text: window.speedtestRunning ? "Running" : "Start Test"
                            }
                        }

                        MouseArea {
                            id: speedtestStartMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: window.speedtestRunning ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: {
                                if (!window.speedtestRunning) {
                                    window.playSfx("switch.wav");
                                    window.runNativeSpeedtest();
                                }
                            }
                        }
                    }
                }
            }
            // END user-addon: speedtest panel

"""

SPEEDTEST_COMPONENT_BLOCK = """            // BEGIN user-addon: speedtest panel
            SpeedtestComponents.SpeedtestPanel {
                id: speedtestPanel
                rootWindow: window
                anchors.fill: parent
                anchors.margins: window.s(18)
                anchors.bottomMargin: window.s(86)
            }
            // END user-addon: speedtest panel

"""

SPEEDTEST_BUTTON_BLOCK = """            // BEGIN user-addon: speedtest button
            Item {
                id: speedtestButtonContainer
                z: 101
                width: window.s(48)
                height: width
                x: parent.width - window.s(30) - window.s(104)
                y: parent.height - window.s(30) - window.s(48)
                visible: window.ethPresent || window.wifiPresent || window.btPresent

                MultiEffect {
                    source: speedtestBtnRect
                    anchors.fill: speedtestBtnRect
                    shadowEnabled: true
                    shadowColor: "#000000"
                    shadowOpacity: 0.35
                    shadowBlur: 1.0
                    shadowVerticalOffset: window.s(4)
                }

                Rectangle {
                    id: speedtestBtnRect
                    anchors.fill: parent
                    radius: width / 2
                    scale: speedtestButtonMa.pressed ? 0.95 : (speedtestButtonMa.containsMouse ? 1.05 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    color: window.showSpeedtestPanel ? window.activeColor : window.surface0
                    border.color: window.speedtestRunning ? window.activeColor : window.surface2
                    border.width: window.s(2)
                    Behavior on color { ColorAnimation { duration: 220 } }
                    Behavior on border.color { ColorAnimation { duration: 220 } }

                    Image {
                        anchors.centerIn: parent
                        width: window.s(27)
                        height: width
                        source: Qt.resolvedUrl("speed-alt-svgrepo-com.svg")
                        opacity: window.showSpeedtestPanel ? 0.72 : 0.95
                        smooth: true
                    }

                    Rectangle {
                        width: window.s(10)
                        height: width
                        radius: width / 2
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: window.s(2)
                        anchors.bottomMargin: window.s(2)
                        color: window.speedtestRunning ? window.peach : (window.speedtestState === "ok" ? window.sapphire : "transparent")
                        visible: window.speedtestRunning || window.speedtestState === "ok"
                    }

                    MouseArea {
                        id: speedtestButtonMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            window.playSfx("switch.wav");
                            window.showSpeedtestPanel = !window.showSpeedtestPanel;
                            if (window.showSpeedtestPanel && window.speedtestState === "idle") window.runNativeSpeedtest();
                        }
                    }
                }
            }
            // END user-addon: speedtest button

"""

OLD_WIFI_INFO_BLOCK = """                    if (window.speedtestRunning) {
                        nodes.push({ id: "speedtest_running_" + i, name: "Running...", icon: "󰓅", action: "Native Speedtest", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    } else if (window.speedtestState === "ok") {
                        nodes.push({ id: "speedtest_down_" + i, name: window.speedtestDownload + " Mbps", icon: "󰇚", action: "Download", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                        nodes.push({ id: "speedtest_up_" + i, name: window.speedtestUpload + " Mbps", icon: "󰕒", action: "Upload", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                        nodes.push({ id: "speedtest_ping_" + i, name: window.speedtestLatency + " ms", icon: "󰔟", action: window.speedtestServer !== "" ? window.speedtestServer : "Latency", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    } else if (window.speedtestState === "error") {
                        nodes.push({ id: "speedtest_error_" + i, name: window.speedtestMessage !== "" ? window.speedtestMessage : "Speedtest failed", icon: "󰅙", action: "Native Speedtest", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    }
                    nodes.push({ id: "speedtest_action_" + i, name: window.speedtestRunning ? "Testing..." : "Run Speedtest", icon: "󰓅", action: window.speedtestRunning ? "Please wait" : (window.speedtestSummary !== "" ? window.speedtestSummary : "Cloudflare native test"), isInfoNode: true, isActionable: !window.speedtestRunning, cmdStr: "RUN_SPEEDTEST", parentIndex: -1 });
"""

OLD_WIFI_LIST_BLOCK = """                newNetworks.push({
                    id: "action_speedtest",
                    ssid: "Native Speedtest",
                    mac: "",
                    name: window.speedtestRunning ? "Testing..." : "Run Speedtest",
                    icon: "󰓅",
                    security: "",
                    action: window.speedtestRunning ? "Please wait" : (window.speedtestSummary !== "" ? window.speedtestSummary : "Cloudflare native test"),
                    isInfoNode: true,
                    isActionable: !window.speedtestRunning,
                    cmdStr: "RUN_SPEEDTEST",
                    parentIndex: -1
                });
"""

OLD_RUN_HANDLER = """                                        } else if (cmdStr === "RUN_SPEEDTEST") {
                                            window.playSfx("switch.wav");
                                            window.runNativeSpeedtest();
                                            floatCard.triggered = false;
                                            drainAnim.start();
"""


class PatchError(RuntimeError):
    pass


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent, text=True)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
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


def install_assets() -> bool:
    changed = False
    for name in (
        "native_speedtest.sh",
        "speed-alt-svgrepo-com.svg",
        "SpeedtestPanel.qml",
    ):
        source = ADDON_DIR / name
        target = NETWORK_DIR / name
        if not source.is_file():
            raise PatchError(f"missing addon asset: {source}")
        if name.endswith(".qml"):
            validate_qml(source)
        if target.is_file() and target.read_bytes() == source.read_bytes():
            continue
        shutil.copy2(source, target)
        if name.endswith(".sh"):
            target.chmod(0o755)
        changed = True
    return changed


def replace_marked_block(text: str, marker: str, replacement: str) -> str:
    begin = f"    // BEGIN user-addon: {marker} state"
    end = f"    // END user-addon: {marker} state"
    start = text.find(begin)
    if start == -1:
        return text
    finish = text.find(end, start)
    if finish == -1:
        raise PatchError(f"{marker} state end marker not found")
    finish += len(end)
    if finish < len(text) and text[finish] == "\n":
        finish += 1
    return text[:start] + replacement + text[finish:]


def remove_marked_item(text: str, marker: str) -> str:
    begin = f"            // BEGIN user-addon: {marker}"
    end = f"            // END user-addon: {marker}"
    start = text.find(begin)
    if start == -1:
        return text
    finish = text.find(end, start)
    if finish == -1:
        raise PatchError(f"{marker} end marker not found")
    finish += len(end)
    while finish < len(text) and text[finish] == "\n":
        finish += 1
    return text[:start] + text[finish:]


def patch_popup(text: str) -> str:
    if "BEGIN user-addon: speedtest import" not in text:
        anchor = 'import "../"\n'
        if anchor not in text:
            raise PatchError("network component import anchor not found")
        text = text.replace(anchor, anchor + IMPORT_BLOCK, 1)

    text = replace_marked_block(text, "speedtest", STATE_BLOCK)
    text = remove_marked_item(text, "speedtest panel")
    text = remove_marked_item(text, "speedtest button")
    text = text.replace(OLD_WIFI_INFO_BLOCK, "")
    text = text.replace(OLD_WIFI_LIST_BLOCK, "")
    text = text.replace(OLD_RUN_HANDLER, "")

    if "BEGIN user-addon: speedtest state" not in text:
        anchor = '    readonly property string scriptsDir: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/network"\n'
        if anchor not in text:
            raise PatchError("network scriptsDir anchor not found")
        text = text.replace(anchor, anchor + "\n" + STATE_BLOCK, 1)

    if "BEGIN user-addon: speedtest panel" not in text:
        anchor = "            Rectangle {\n                id: bottomTabsContainer\n"
        if anchor not in text:
            raise PatchError("bottom tabs anchor not found")
        text = text.replace(anchor, SPEEDTEST_COMPONENT_BLOCK + anchor, 1)

    if "BEGIN user-addon: speedtest button" not in text:
        anchor = "            Item {\n                id: powerToggleContainer\n"
        if anchor not in text:
            raise PatchError("power toggle anchor not found")
        text = text.replace(anchor, SPEEDTEST_BUTTON_BLOCK + anchor, 1)

    return text


def main() -> int:
    if not NETWORK_POPUP.is_file():
        raise PatchError(f"active NetworkPopup not found: {NETWORK_POPUP}")

    original = NETWORK_POPUP.read_text(encoding="utf-8")
    patched = patch_popup(original)

    validate_qml(NETWORK_POPUP)
    assets_changed = install_assets()

    if patched != original:
        tmp_path = NETWORK_DIR / ".NetworkPopup.qml.speedtest-preview"
        atomic_write(tmp_path, patched)
        try:
            validate_qml(tmp_path)
        finally:
            tmp_path.unlink(missing_ok=True)
        backup(NETWORK_POPUP)
        atomic_write(NETWORK_POPUP, patched)

    status: list[str] = []
    if patched != original:
        status.append("popup")
    if assets_changed:
        status.append("assets")
    print("speedtest: updated " + ", ".join(status) if status else "speedtest: addon already installed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"speedtest: {error}; no core file changed", file=sys.stderr)
        raise SystemExit(1)
