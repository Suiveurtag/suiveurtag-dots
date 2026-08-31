import QtQuick
import QtQuick.Layouts
import "." as AlarmSystem

Item {
    id: root

    property var scaleFunc: function(value) { return value; }
    property color mantleColor: "#181825"
    property color surface0Color: "#313244"
    property color surface1Color: "#45475a"
    property color textColor: "#cdd6f4"
    property color subtextColor: "#a6adc8"
    property color accentColor: "#cba6f7"
    property string iconFont: "Font Awesome 6 Free Solid"

    visible: AlarmSystem.AlarmManager.isRinging
    z: 250

    function s(value) {
        return typeof scaleFunc === "function" ? scaleFunc(value) : value;
    }

    Rectangle {
        anchors.fill: parent
        color: "#b3000000"

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - root.s(36), root.s(310))
        height: root.s(188)
        radius: root.s(16)
        color: root.mantleColor
        border.width: 2
        border.color: root.accentColor

        Rectangle {
            id: bellCircle
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: root.s(17)
            width: root.s(54)
            height: width
            radius: width / 2
            color: root.accentColor

            SequentialAnimation on scale {
                running: root.visible
                loops: Animation.Infinite
                NumberAnimation { to: 1.1; duration: 420; easing.type: Easing.OutCubic }
                NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InCubic }
            }

            Text {
                anchors.centerIn: parent
                text: "\uF0F3"
                color: root.mantleColor
                font.family: root.iconFont
                font.pixelSize: root.s(23)
            }
        }

        ColumnLayout {
            anchors.top: bellCircle.bottom
            anchors.topMargin: root.s(9)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: root.s(18)
            anchors.rightMargin: root.s(18)
            anchors.bottomMargin: root.s(14)
            spacing: root.s(4)

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: AlarmSystem.AlarmManager.ringingTitle
                elide: Text.ElideRight
                color: root.textColor
                font.family: "JetBrains Mono"
                font.weight: Font.Black
                font.pixelSize: root.s(16)
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: AlarmSystem.AlarmManager.ringingMessage
                elide: Text.ElideRight
                color: root.subtextColor
                font.family: "JetBrains Mono"
                font.pixelSize: root.s(10)
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: root.s(8)

                Rectangle {
                    Layout.fillWidth: true
                    height: root.s(34)
                    visible: AlarmSystem.AlarmManager.ringingMode === "alarm"
                    radius: root.s(9)
                    color: snoozeMouse.containsMouse ? root.surface1Color : root.surface0Color
                    border.width: 1
                    border.color: root.surface1Color

                    Text {
                        anchors.centerIn: parent
                        text: "Snooze 5 min"
                        color: root.textColor
                        font.family: "JetBrains Mono"
                        font.bold: true
                        font.pixelSize: root.s(10)
                    }

                    MouseArea {
                        id: snoozeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: AlarmSystem.AlarmManager.snoozeCurrent(5)
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: root.s(34)
                    radius: root.s(9)
                    color: root.accentColor

                    Text {
                        anchors.centerIn: parent
                        text: "Dismiss"
                        color: root.mantleColor
                        font.family: "JetBrains Mono"
                        font.bold: true
                        font.pixelSize: root.s(10)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: AlarmSystem.AlarmManager.stopPlayback(true)
                    }
                }
            }
        }
    }

    Shortcut {
        enabled: root.visible
        sequence: "Escape"
        onActivated: AlarmSystem.AlarmManager.stopPlayback(true)
    }
}
