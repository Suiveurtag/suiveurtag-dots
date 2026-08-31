import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Rectangle {
    id: root

    property real uiScale: 1
    property bool highlighted: false
    property bool idleDisabled: false
    property bool applying: false
    property color accentColor: "#74c7ec"
    property color baseColor: "#1e1e2e"
    property color textColor: "#cdd6f4"
    property color subtextColor: "#a6adc8"
    property color surface0Color: "#313244"
    property color surface1Color: "#45475a"
    property color surface2Color: "#585b70"

    signal selected()

    function s(value) { return value * uiScale; }

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || (homeDir + "/.local/share")
    property string settingsPath: homeDir + "/.config/hypr/settings.json"
    readonly property string applyScript: dataHome + "/quickshell-addons/idle-inhibit/apply.sh"

    function toggle() {
        if (applying) return;
        const requestedState = !idleDisabled;
        idleDisabled = requestedState;
        applying = true;
        applyProcess.command = [applyScript, requestedState ? "--disable" : "--enable"];
        applyProcess.running = true;
    }

    Layout.fillWidth: true
    Layout.preferredHeight: contentRow.implicitHeight + s(28)
    radius: s(12)
    color: highlighted ? accentColor : surface0Color
    border.color: highlighted ? accentColor : surface1Color
    border.width: 1

    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

    MouseArea {
        anchors.fill: parent
        onClicked: root.selected()
        z: -1
    }

    RowLayout {
        id: contentRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.s(16)
        spacing: root.s(14)

        Item {
            Layout.preferredWidth: root.s(22)
            Layout.alignment: Qt.AlignVCenter
            Text {
                anchors.centerIn: parent
                text: "󰒲"
                font.family: "Iosevka Nerd Font"
                font.pixelSize: root.s(18)
                color: root.highlighted ? root.baseColor : root.accentColor
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: root.s(3)
            Text {
                text: "Disable idle sleep and lock"
                font.family: "Inter"
                font.weight: Font.Medium
                font.pixelSize: root.s(14)
                color: root.highlighted ? root.baseColor : root.textColor
                Layout.fillWidth: true
            }
            Text {
                text: "Keep the session awake until this option is turned off"
                font.family: "Inter"
                font.pixelSize: root.s(11)
                color: root.highlighted ? Qt.alpha(root.baseColor, 0.75) : Qt.alpha(root.subtextColor, 0.7)
                Layout.fillWidth: true
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            Layout.preferredWidth: root.s(40)
            Layout.preferredHeight: root.s(22)
            radius: root.s(11)
            scale: toggleMouse.containsMouse ? 1.05 : 1.0
            opacity: root.applying ? 0.55 : 1.0
            color: root.idleDisabled
                ? (root.highlighted ? root.baseColor : root.accentColor)
                : Qt.alpha(root.surface2Color, root.highlighted ? 0.4 : 1.0)

            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
            Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

            Rectangle {
                width: root.s(16)
                height: root.s(16)
                radius: root.s(8)
                y: root.s(3)
                x: root.idleDisabled ? root.s(21) : root.s(3)
                color: root.idleDisabled
                    ? (root.highlighted ? root.accentColor : root.baseColor)
                    : (root.highlighted ? root.accentColor : root.surface0Color)
                Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
            }

            MouseArea {
                id: toggleMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !root.applying
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggle()
            }
        }
    }

    Process {
        id: settingsReader
        command: ["cat", root.settingsPath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const settings = JSON.parse(this.text || "{}");
                    root.idleDisabled = settings.disableIdleTimeouts === true;
                } catch (error) {
                    root.idleDisabled = false;
                }
            }
        }
    }

    Process {
        id: applyProcess
        onExited: exitCode => {
            root.applying = false;
            if (exitCode !== 0) root.idleDisabled = !root.idleDisabled;
            settingsReader.running = false;
            settingsReader.running = true;
        }
    }

    Component.onCompleted: settingsReader.running = true
}
