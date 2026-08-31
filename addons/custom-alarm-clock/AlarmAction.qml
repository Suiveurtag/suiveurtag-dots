import QtQuick
import "alarm" as AlarmSystem
import "../../singletons"

Item {
    id: root

    property int requestedLayoutTemplate: 1
    property real preferredWidth: s(430)
    property real preferredExtraLength: s(500)
    property var themeColors: typeof mochaColors !== "undefined" ? mochaColors : null
    property string currentEdge: typeof activeEdge !== "undefined" ? activeEdge : "left"

    function s(value) {
        return typeof scaleFunc !== "undefined" ? scaleFunc(value) : value;
    }

    Item {
        anchors.centerIn: parent
        width: root.currentEdge === "bottom" || root.currentEdge === "top" ? parent.height : parent.width
        height: root.currentEdge === "bottom" || root.currentEdge === "top" ? parent.width : parent.height
        rotation: root.currentEdge === "right" ? 180 : (root.currentEdge === "bottom" ? 90 : (root.currentEdge === "top" ? -90 : 0))

        Rectangle {
            anchors.fill: parent
            radius: root.s(12)
            color: root.themeColors.base

            Text {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: root.s(18)
                text: "Alarmes"
                color: root.themeColors.text
                font.pixelSize: root.s(18)
                font.bold: true
            }

            Text {
                anchors.right: soundButton.left
                anchors.rightMargin: root.s(10)
                anchors.verticalCenter: soundButton.verticalCenter
                width: Math.max(0, parent.width - root.s(190))
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: AlarmSystem.AlarmManager.nextAlarmText() || "Aucune alarme active"
                color: root.themeColors.subtext0
                font.pixelSize: root.s(10)
            }

            Rectangle {
                id: soundButton
                anchors.right: addButton.left
                anchors.rightMargin: root.s(8)
                anchors.top: parent.top
                anchors.topMargin: root.s(13)
                width: root.s(34)
                height: width
                radius: width / 2
                color: soundMouse.containsMouse ? root.themeColors.surface1 : root.themeColors.surface0

                Text {
                    anchors.centerIn: parent
                    text: "\uF001"
                    color: root.themeColors.text
                    font.family: "Font Awesome 6 Free Solid"
                    font.pixelSize: root.s(12)
                }

                MouseArea {
                    id: soundMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: soundSettings.openFor("alarm")
                }
            }

            Rectangle {
                id: addButton
                anchors.right: parent.right
                anchors.rightMargin: root.s(14)
                anchors.top: parent.top
                anchors.topMargin: root.s(13)
                width: root.s(34)
                height: width
                radius: width / 2
                color: root.themeColors.mauve

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: root.themeColors.mantle
                    font.pixelSize: root.s(22)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: alarmView.openNewAlarm()
                }
            }

            AlarmSystem.AlarmView {
                id: alarmView
                anchors.fill: parent
                anchors.topMargin: root.s(58)
                anchors.leftMargin: root.s(14)
                anchors.rightMargin: root.s(14)
                anchors.bottomMargin: root.s(14)
                scaleFunc: root.s
                baseColor: root.themeColors.base
                mantleColor: root.themeColors.mantle
                surface0Color: root.themeColors.surface0
                surface1Color: root.themeColors.surface1
                textColor: root.themeColors.text
                subtextColor: root.themeColors.subtext0
                accentColor: root.themeColors.mauve
            }

            AlarmSystem.SoundSettings {
                id: soundSettings
                anchors.fill: parent
                scaleFunc: root.s
                baseColor: root.themeColors.base
                mantleColor: root.themeColors.mantle
                surface0Color: root.themeColors.surface0
                surface1Color: root.themeColors.surface1
                textColor: root.themeColors.text
                subtextColor: root.themeColors.subtext0
                accentColor: root.themeColors.mauve
            }

            AlarmSystem.RingingOverlay {
                anchors.fill: parent
                scaleFunc: root.s
                mantleColor: root.themeColors.mantle
                surface0Color: root.themeColors.surface0
                surface1Color: root.themeColors.surface1
                textColor: root.themeColors.text
                subtextColor: root.themeColors.subtext0
                accentColor: root.themeColors.mauve
            }
        }
    }
}
