import QtQuick
import QtQuick.Effects

Rectangle {
    id: root

    property real uiScale: 1
    property bool active: false
    property bool available: true
    property color textColor: "white"
    property color surface1Color: "#444444"
    property color surface2Color: "#666666"

    signal triggered()

    width: 44 * uiScale
    height: 44 * uiScale
    radius: 10 * uiScale
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    color: active ? surface2Color : "transparent"
    border.color: active ? textColor : surface1Color
    border.width: active ? 2 * uiScale : 1
    scale: active ? 1.15 : (mouseArea.containsMouse ? 1.08 : 1.0)
    opacity: available ? 1.0 : 0.45

    Behavior on color { ColorAnimation { duration: 300 } }
    Behavior on border.color { ColorAnimation { duration: 300 } }
    Behavior on scale {
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }
    }

    Image {
        id: randomIcon
        anchors.centerIn: parent
        width: 20 * root.uiScale
        height: 20 * root.uiScale
        source: Qt.resolvedUrl("random.svg")
        fillMode: Image.PreserveAspectFit
        sourceSize: Qt.size(64, 64)
        visible: false
    }

    MultiEffect {
        anchors.fill: randomIcon
        source: randomIcon
        brightness: 1.0
        saturation: 0.0
        colorization: 1.0
        colorizationColor: root.active || mouseArea.containsMouse
            ? root.textColor
            : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.7)
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.available
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.triggered()
    }
}
