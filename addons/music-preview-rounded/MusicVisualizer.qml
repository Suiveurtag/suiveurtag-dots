import QtQuick

Item {
    id: root

    property real uiScale: 1
    property color primaryColor: "#cba6f7"
    property color secondaryColor: "#89b4fa"
    property color backgroundColor: "#313244"
    signal activated()

    function s(value) { return value * uiScale; }

    implicitWidth: s(82)
    implicitHeight: s(28)

    Rectangle {
        anchors.fill: parent
        radius: root.s(10)
        color: Qt.alpha(root.backgroundColor, visualizerMouse.containsMouse ? 0.92 : 0.72)
        border.width: 1
        border.color: Qt.alpha(root.primaryColor, visualizerMouse.containsMouse ? 0.45 : 0.18)

        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }

        Row {
            anchors.centerIn: parent
            spacing: root.s(2)

            Repeater {
                model: 12
                Rectangle {
                    required property int index
                    width: root.s(3.5)
                    height: Math.max(root.s(3), root.s(20) * MusicVisualizerData.bands[index])
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter

                    gradient: Gradient {
                        GradientStop { position: 0.0; color: root.secondaryColor }
                        GradientStop { position: 1.0; color: root.primaryColor }
                    }

                    Behavior on height {
                        NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                    }
                }
            }
        }

        MouseArea {
            id: visualizerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activated()
        }
    }
}
