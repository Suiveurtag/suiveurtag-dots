import QtQuick

Item {
    id: root

    property real uiScale: 1
    property color primaryColor: "#cba6f7"
    property color secondaryColor: "#89b4fa"
    property color backgroundColor: "#313244"
    signal activated()

    function s(value) { return value * uiScale; }

    implicitWidth: s(94)
    implicitHeight: s(32)

    Row {
        anchors.centerIn: parent
        spacing: root.s(2.5)
        opacity: visualizerMouse.containsMouse ? 1.0 : 0.88

        Behavior on opacity { NumberAnimation { duration: 160 } }

        Repeater {
            model: 12
            Rectangle {
                required property int index
                width: root.s(4)
                height: Math.max(root.s(4), root.s(33) * Math.pow(MusicVisualizerData.bands[index], 0.7))
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

    SequentialAnimation {
        id: clickPulse
        NumberAnimation { target: root; property: "scale"; to: 0.86; duration: 65; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "scale"; to: 1.08; duration: 105; easing.type: Easing.OutBack }
        NumberAnimation { target: root; property: "scale"; to: 1.0; duration: 130; easing.type: Easing.OutCubic }
    }

    MouseArea {
        id: visualizerMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            clickPulse.restart();
            root.activated();
        }
    }
}
