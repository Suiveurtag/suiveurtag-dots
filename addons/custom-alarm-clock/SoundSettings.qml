import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import QtCore
import "." as AlarmSystem

Item {
    id: root

    property string mode: "timer"
    property var scaleFunc: function(value) { return value; }
    property color baseColor: "#1e1e2e"
    property color mantleColor: "#181825"
    property color surface0Color: "#313244"
    property color surface1Color: "#45475a"
    property color textColor: "#cdd6f4"
    property color subtextColor: "#a6adc8"
    property color accentColor: "#cba6f7"
    property string iconFont: "Font Awesome 6 Free Solid"
    property int pendingVolume: 85
    property int pendingTargetMs: 5 * 60 * 1000
    property bool opened: false

    visible: opened || opacity > 0.001
    opacity: opened ? 1 : 0
    z: 200

    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    function s(value) {
        return typeof scaleFunc === "function" ? scaleFunc(value) : value;
    }

    function openFor(selectedMode) {
        mode = selectedMode;
        pendingVolume = AlarmSystem.AlarmManager.soundFor(mode).volume;
        pendingTargetMs = AlarmSystem.AlarmManager.stopwatchTargetMs;
        opened = true;
    }

    function close() {
        if (AlarmSystem.AlarmManager.isPreviewing) {
            AlarmSystem.AlarmManager.stopPlayback(false);
        }
        opened = false;
    }

    function updateVolumeAt(positionX, totalWidth) {
        pendingVolume = Math.max(0, Math.min(100, Math.round(positionX / totalWidth * 100)));
    }

    function targetText() {
        let totalSeconds = Math.floor(pendingTargetMs / 1000);
        let hours = Math.floor(totalSeconds / 3600);
        let minutes = Math.floor((totalSeconds % 3600) / 60);
        let seconds = totalSeconds % 60;
        return String(hours).padStart(2, "0") + ":"
            + String(minutes).padStart(2, "0") + ":"
            + String(seconds).padStart(2, "0");
    }

    component ActionButton: Rectangle {
        property string label: ""
        property bool accented: false
        signal clicked()

        implicitWidth: root.s(88)
        implicitHeight: root.s(34)
        radius: root.s(9)
        color: accented ? root.accentColor : (buttonMouse.containsMouse ? root.surface1Color : root.surface0Color)
        border.width: accented ? 0 : 1
        border.color: root.surface1Color
        scale: buttonMouse.pressed ? 0.94 : 1

        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: 180 } }

        Text {
            anchors.centerIn: parent
            text: parent.label
            color: parent.accented ? root.mantleColor : root.textColor
            font.family: "JetBrains Mono"
            font.pixelSize: root.s(11)
            font.bold: true
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    FileDialog {
        id: soundDialog
        title: "Choose alarm sound"
        currentFolder: {
            const locations = StandardPaths.standardLocations(StandardPaths.MusicLocation);
            return locations.length > 0 ? locations[0] : StandardPaths.writableLocation(StandardPaths.HomeLocation);
        }
        nameFilters: [
            "Audio files (*.wav *.ogg *.oga *.mp3 *.flac *.m4a *.aac *.opus)",
            "All files (*)"
        ]
        onAccepted: {
            AlarmSystem.AlarmManager.setSound(root.mode, selectedFile);
            AlarmSystem.AlarmManager.preview(root.mode);
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.opened ? "#99000000" : "#00000000"

        Behavior on color { ColorAnimation { duration: 220 } }

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - root.s(28), root.s(330))
        height: root.mode === "stopwatch" ? root.s(282) : root.s(230)
        radius: root.s(14)
        color: root.mantleColor
        border.width: 1
        border.color: root.surface1Color
        opacity: root.opened ? 1 : 0
        scale: root.opened ? 1 : 0.82

        Behavior on opacity { NumberAnimation { duration: 240 } }
        Behavior on scale {
            NumberAnimation { duration: 380; easing.type: Easing.OutBack }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: mouse => mouse.accepted = true
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.s(16)
            spacing: root.s(11)

            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: AlarmSystem.AlarmManager.modeLabel(root.mode) + " sound"
                        color: root.textColor
                        font.family: "JetBrains Mono"
                        font.pixelSize: root.s(16)
                        font.weight: Font.Black
                    }
                    Text {
                        text: "Custom alarm profile"
                        color: root.subtextColor
                        font.family: "JetBrains Mono"
                        font.pixelSize: root.s(10)
                    }
                }

                Rectangle {
                    width: root.s(30)
                    height: width
                    radius: root.s(8)
                    color: closeMouse.containsMouse ? root.surface1Color : "transparent"
                    scale: closeMouse.pressed ? 0.84 : 1

                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                    Text {
                        anchors.centerIn: parent
                        text: "\uF00D"
                        color: root.textColor
                        font.family: root.iconFont
                        font.pixelSize: root.s(13)
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: root.s(42)
                radius: root.s(9)
                color: root.surface0Color
                border.width: 1
                border.color: root.surface1Color

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: root.s(12)
                    anchors.rightMargin: root.s(12)
                    spacing: root.s(9)

                    Text {
                        text: "\uF001"
                        color: root.accentColor
                        font.family: root.iconFont
                        font.pixelSize: root.s(13)
                    }
                    Text {
                        Layout.fillWidth: true
                        text: AlarmSystem.AlarmManager.soundName(root.mode)
                        elide: Text.ElideMiddle
                        color: root.textColor
                        font.family: "JetBrains Mono"
                        font.pixelSize: root.s(11)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: root.s(8)

                ActionButton {
                    label: "Choose…"
                    Layout.fillWidth: true
                    onClicked: soundDialog.open()
                }
                ActionButton {
                    label: AlarmSystem.AlarmManager.previewMode === root.mode ? "Stop test" : "Test"
                    Layout.fillWidth: true
                    accented: AlarmSystem.AlarmManager.previewMode === root.mode
                    onClicked: {
                        if (AlarmSystem.AlarmManager.previewMode === root.mode) {
                            AlarmSystem.AlarmManager.stopPlayback(false);
                        } else {
                            AlarmSystem.AlarmManager.preview(root.mode);
                        }
                    }
                }
                ActionButton {
                    label: "Reset"
                    Layout.fillWidth: true
                    onClicked: AlarmSystem.AlarmManager.resetSound(root.mode)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: root.s(10)

                Text {
                    text: "\uF028"
                    color: root.subtextColor
                    font.family: root.iconFont
                    font.pixelSize: root.s(12)
                }

                Rectangle {
                    id: volumeTrack
                    Layout.fillWidth: true
                    height: root.s(8)
                    radius: height / 2
                    color: root.surface0Color

                    Rectangle {
                        width: parent.width * root.pendingVolume / 100
                        height: parent.height
                        radius: height / 2
                        color: root.accentColor
                    }

                    Rectangle {
                        x: Math.max(0, Math.min(parent.width - width, parent.width * root.pendingVolume / 100 - width / 2))
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.s(16)
                        height: width
                        radius: width / 2
                        color: root.textColor
                        border.width: 2
                        border.color: root.accentColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -root.s(8)
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => root.updateVolumeAt(mouse.x, width)
                        onPositionChanged: mouse => {
                            if (pressed) root.updateVolumeAt(mouse.x, width);
                        }
                        onReleased: AlarmSystem.AlarmManager.setVolume(root.mode, root.pendingVolume)
                    }
                }

                Text {
                    text: root.pendingVolume + "%"
                    color: root.textColor
                    font.family: "JetBrains Mono"
                    font.bold: true
                    font.pixelSize: root.s(11)
                    Layout.minimumWidth: root.s(36)
                    horizontalAlignment: Text.AlignRight
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: root.s(52)
                visible: root.mode === "stopwatch"
                radius: root.s(10)
                color: root.surface0Color
                border.width: 1
                border.color: root.surface1Color

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: root.s(10)
                    anchors.rightMargin: root.s(10)
                    spacing: root.s(8)

                    Rectangle {
                        width: root.s(28)
                        height: width
                        radius: root.s(7)
                        color: targetMinus.containsMouse ? root.surface1Color : root.mantleColor
                        Text {
                            anchors.centerIn: parent
                            text: "−"
                            color: root.textColor
                            font.family: "JetBrains Mono"
                            font.bold: true
                        }
                        MouseArea {
                            id: targetMinus
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.pendingTargetMs = Math.max(60000, root.pendingTargetMs - 60000);
                                AlarmSystem.AlarmManager.setStopwatchTarget(
                                    root.pendingTargetMs,
                                    AlarmSystem.AlarmManager.stopwatchEnabled
                                );
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: "Alert at " + root.targetText()
                            color: root.textColor
                            font.family: "JetBrains Mono"
                            font.bold: true
                            font.pixelSize: root.s(11)
                        }
                        Text {
                            text: "Optional count-up target"
                            color: root.subtextColor
                            font.family: "JetBrains Mono"
                            font.pixelSize: root.s(9)
                        }
                    }

                    Rectangle {
                        width: root.s(28)
                        height: width
                        radius: root.s(7)
                        color: targetPlus.containsMouse ? root.surface1Color : root.mantleColor
                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            color: root.textColor
                            font.family: "JetBrains Mono"
                            font.bold: true
                        }
                        MouseArea {
                            id: targetPlus
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.pendingTargetMs = Math.min(99 * 3600000, root.pendingTargetMs + 60000);
                                AlarmSystem.AlarmManager.setStopwatchTarget(
                                    root.pendingTargetMs,
                                    AlarmSystem.AlarmManager.stopwatchEnabled
                                );
                            }
                        }
                    }

                    Rectangle {
                        width: root.s(42)
                        height: root.s(24)
                        radius: height / 2
                        color: AlarmSystem.AlarmManager.stopwatchEnabled ? root.accentColor : root.surface1Color

                        Rectangle {
                            width: root.s(18)
                            height: width
                            radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            x: AlarmSystem.AlarmManager.stopwatchEnabled
                                ? parent.width - width - root.s(3)
                                : root.s(3)
                            color: AlarmSystem.AlarmManager.stopwatchEnabled ? root.mantleColor : root.subtextColor
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: AlarmSystem.AlarmManager.setStopwatchTarget(
                                root.pendingTargetMs,
                                !AlarmSystem.AlarmManager.stopwatchEnabled
                            )
                        }
                    }
                }
            }
        }
    }

    Shortcut {
        enabled: root.visible
        sequence: "Escape"
        onActivated: root.close()
    }
}
