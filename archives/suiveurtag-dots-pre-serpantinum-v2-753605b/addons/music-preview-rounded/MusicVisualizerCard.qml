import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Rectangle {
    id: root

    property real uiScale: 1
    property bool highlighted: false
    property bool visualizerEnabled: false
    property bool applying: false
    property color accentColor: "#cba6f7"
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
    readonly property string applyScript: dataHome + "/quickshell-addons/music-preview-rounded/apply.sh"

    function toggle() {
        if (applying) return;
        const requestedState = !visualizerEnabled;
        visualizerEnabled = requestedState;
        applying = true;
        applyProcess.command = [applyScript, requestedState ? "--enable" : "--disable"];
        applyProcess.running = true;
    }

    Layout.fillWidth: true
    Layout.preferredHeight: contentRow.implicitHeight + s(28)
    radius: s(12)
    color: highlighted ? accentColor : surface0Color
    border.color: highlighted ? accentColor : surface1Color
    border.width: 1

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
                text: "󰎆"
                font.family: "Iosevka Nerd Font"
                font.pixelSize: root.s(18)
                color: root.highlighted ? root.baseColor : root.accentColor
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: root.s(3)
            Text {
                text: "Music visualizer"
                font.family: "Inter"
                font.weight: Font.Medium
                font.pixelSize: root.s(14)
                color: root.highlighted ? root.baseColor : root.textColor
                Layout.fillWidth: true
            }
            Text {
                text: "Replace playback buttons with a CAVA spectrum"
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
            opacity: root.applying ? 0.55 : 1.0
            color: root.visualizerEnabled
                ? (root.highlighted ? root.baseColor : root.accentColor)
                : Qt.alpha(root.surface2Color, root.highlighted ? 0.4 : 1.0)

            Rectangle {
                width: root.s(16)
                height: root.s(16)
                radius: root.s(8)
                y: root.s(3)
                x: root.visualizerEnabled ? root.s(21) : root.s(3)
                color: root.visualizerEnabled
                    ? (root.highlighted ? root.accentColor : root.baseColor)
                    : (root.highlighted ? root.accentColor : root.surface0Color)
                Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
            }

            MouseArea {
                anchors.fill: parent
                enabled: !root.applying
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggle()
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.selected()
        z: -1
    }

    Process {
        id: settingsReader
        command: ["cat", root.settingsPath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const settings = JSON.parse(this.text || "{}");
                    root.visualizerEnabled = settings.musicVisualizerEnabled === true;
                } catch (error) {
                    root.visualizerEnabled = false;
                }
            }
        }
    }

    Process {
        id: applyProcess
        onExited: exitCode => {
            root.applying = false;
            if (exitCode !== 0) root.visualizerEnabled = !root.visualizerEnabled;
            settingsReader.running = false;
            settingsReader.running = true;
        }
    }

    Component.onCompleted: settingsReader.running = true
}
