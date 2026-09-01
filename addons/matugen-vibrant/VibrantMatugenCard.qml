import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../reusables"

Rectangle {
    id: root

    property real uiScale: 1
    property bool highlighted: false
    property string colorMode: "normal"
    property string previousMode: "normal"
    property bool applying: false
    property color accentColor: "#94e2d5"
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
    property string settingsPath: homeDir + "/.config/serpantinum/settings.json"
    readonly property string applyScript: dataHome + "/quickshell-addons/matugen-vibrant/apply.sh"
    readonly property var modeOptions: ["OFF", "NORMAL", "VIVID"]
    readonly property int modeIndex: {
        let index = ["off", "normal", "vivid"].indexOf(root.colorMode);
        return index >= 0 ? index : 1;
    }

    function setModeIndex(index) {
        if (applying || index < 0 || index >= 3) return;
        let modes = ["off", "normal", "vivid"];
        let requestedMode = modes[index];
        if (requestedMode === colorMode) return;
        previousMode = colorMode;
        colorMode = requestedMode;
        applying = true;
        applyProcess.command = [applyScript, "--mode", requestedMode];
        applyProcess.running = true;
    }

    function toggle() {
        setModeIndex(modeIndex === 2 ? 1 : 2);
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
                text: "󰏘"
                font.family: "Iosevka Nerd Font"
                font.pixelSize: root.s(18)
                color: root.highlighted ? root.baseColor : root.accentColor
                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: root.s(3)

            Text {
                text: "Matugen color mode"
                font.family: "Inter"
                font.weight: Font.Medium
                font.pixelSize: root.s(14)
                color: root.highlighted ? root.baseColor : root.textColor
                Layout.fillWidth: true
                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
            }

            Text {
                text: "Off preset · normal wallpaper · vivid lifted colors"
                font.family: "Inter"
                font.pixelSize: root.s(11)
                color: root.highlighted ? Qt.alpha(root.baseColor, 0.75) : Qt.alpha(root.subtextColor, 0.7)
                Layout.fillWidth: true
                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
            }
        }

        Dropdown {
            id: modeSelector
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            Layout.preferredWidth: root.s(180)
            Layout.minimumWidth: root.s(160)
            Layout.preferredHeight: root.s(32)
            enabled: !root.applying
            options: root.modeOptions
            currentIndex: root.modeIndex
            accentColor: root.highlighted ? root.baseColor : root.accentColor
            baseColor: root.surface0Color
            hoverColor: root.surface1Color
            dropdownColor: root.surface0Color
            borderColor: Qt.alpha(root.surface2Color, 0.6)
            textColor: root.highlighted ? Qt.alpha(root.baseColor, 0.86) : root.textColor
            activeTextColor: root.highlighted ? root.accentColor : root.baseColor
            cornerRadius: root.s(11)
            fontPixelSize: root.s(10)
            clickSound: "reusables/dropdown/click.wav"
            listSound: "reusables/dropdown/list.wav"
            onValueChanged: function(index, value) { root.setModeIndex(index); }
        }
    }

    Process {
        id: settingsReader
        command: ["cat", root.settingsPath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let settings = JSON.parse(this.text || "{}");
                    let mode = String(settings.matugenColorMode || "").toLowerCase();
                    if (["off", "normal", "vivid"].indexOf(mode) === -1) {
                        mode = settings.vibrantMatugenColors === true ? "vivid" : "normal";
                    }
                    root.colorMode = mode;
                    root.previousMode = mode;
                } catch (error) {
                    root.colorMode = "normal";
                    root.previousMode = "normal";
                }
            }
        }
    }

    Process {
        id: applyProcess
        onExited: (exitCode) => {
            root.applying = false;
            if (exitCode !== 0) {
                root.colorMode = root.previousMode;
            }
            settingsReader.running = false;
            settingsReader.running = true;
        }
    }

    Component.onCompleted: settingsReader.running = true
}
