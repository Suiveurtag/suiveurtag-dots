import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Rectangle {
    id: root

    property real uiScale: 1
    property bool routingEnabled: false
    property bool applying: false
    property bool available: true
    property string capturedOutput: ""
    property string failureMessage: ""
    property string controlOutput: ""
    property color accentColor: "#a6e3a1"
    property color baseColor: "#1e1e2e"
    property color textColor: "#cdd6f4"
    property color subtextColor: "#a6adc8"
    property color surface0Color: "#313244"
    property color surface1Color: "#45475a"
    property color surface2Color: "#585b70"

    function s(value) { return value * uiScale; }

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || (homeDir + "/.local/share")
    readonly property string controlScript: dataHome + "/quickshell-addons/headset-mic-loopback/loopback.py"

    function refreshStatus() {
        if (statusProcess.running || applyProcess.running) return;
        statusProcess.running = true;
    }

    function toggle() {
        if (applying || !available) return;
        applying = true;
        failureMessage = "";
        controlOutput = "";
        applyProcess.command = [controlScript, routingEnabled ? "disable" : "enable"];
        applyProcess.running = true;
    }

    implicitHeight: s(82)
    radius: s(14)
    color: toggleArea.containsMouse ? "#0affffff" : "#05ffffff"
    border.color: routingEnabled ? accentColor : "#1affffff"
    border.width: routingEnabled ? 2 : 1

    Behavior on color { ColorAnimation { duration: 180 } }
    Behavior on border.color { ColorAnimation { duration: 220 } }

    MouseArea {
        id: toggleArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: !root.applying && root.available
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.toggle()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.s(16)
        anchors.rightMargin: root.s(16)
        spacing: root.s(13)

        Rectangle {
            Layout.preferredWidth: root.s(42)
            Layout.preferredHeight: root.s(42)
            Layout.alignment: Qt.AlignVCenter
            radius: root.s(21)
            color: Qt.alpha(root.accentColor, root.routingEnabled ? 0.28 : 0.12)
            border.color: Qt.alpha(root.accentColor, root.routingEnabled ? 1.0 : 0.45)

            Text {
                anchors.centerIn: parent
                text: "󰍬"
                font.family: "Iosevka Nerd Font"
                font.pixelSize: root.s(22)
                color: root.accentColor
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: root.s(3)

            Text {
                Layout.fillWidth: true
                text: "Headset audio as microphone"
                elide: Text.ElideRight
                font.family: "JetBrains Mono"
                font.weight: Font.Bold
                font.pixelSize: root.s(13)
                color: root.textColor
            }

            Text {
                Layout.fillWidth: true
                text: {
                    if (root.failureMessage !== "") return root.failureMessage;
                    if (!root.available) return "PipeWire loopback is unavailable";
                    if (root.applying) return root.routingEnabled ? "Removing virtual input..." : "Creating virtual input...";
                    if (root.routingEnabled) return "Headset Audio • " + (root.capturedOutput || "current output");
                    return "Expose the current output as the Headset Audio input";
                }
                elide: Text.ElideRight
                font.family: "JetBrains Mono"
                font.pixelSize: root.s(10)
                color: root.failureMessage !== "" ? "#f38ba8" : root.subtextColor
            }
        }

        Rectangle {
            Layout.preferredWidth: root.s(42)
            Layout.preferredHeight: root.s(24)
            Layout.alignment: Qt.AlignVCenter
            radius: root.s(12)
            opacity: root.applying ? 0.55 : 1.0
            color: root.routingEnabled ? root.accentColor : root.surface2Color

            Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

            Rectangle {
                width: root.s(18)
                height: root.s(18)
                radius: root.s(9)
                y: root.s(3)
                x: root.routingEnabled ? root.s(21) : root.s(3)
                color: root.routingEnabled ? root.baseColor : root.surface0Color
                Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
            }
        }
    }

    Process {
        id: statusProcess
        command: [root.controlScript, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const state = JSON.parse(this.text || "{}");
                    root.routingEnabled = state.enabled === true;
                    root.capturedOutput = state.output || "";
                    root.available = true;
                } catch (error) {
                    root.available = false;
                }
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) root.available = false;
        }
    }

    Process {
        id: applyProcess
        stdout: StdioCollector { onStreamFinished: root.controlOutput = this.text.trim() }
        stderr: StdioCollector { onStreamFinished: root.failureMessage = this.text.trim().replace(/^headset-mic-loopback:\s*/, "") }
        onExited: exitCode => {
            root.applying = false;
            if (exitCode === 0 && root.controlOutput !== "") {
                try {
                    const state = JSON.parse(root.controlOutput);
                    root.routingEnabled = state.enabled === true;
                    root.capturedOutput = state.output || "";
                    root.failureMessage = "";
                } catch (error) {
                    root.refreshStatus();
                }
            } else {
                root.refreshStatus();
            }
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root.refreshStatus()
    }
}
