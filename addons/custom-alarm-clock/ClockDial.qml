import QtQuick

Item {
    id: root

    property var scaleFunc: function(value) { return value; }
    property color primaryColor: "#cba6f7"
    property color secondaryColor: "#89b4fa"
    property color surfaceColor: "#313244"
    property color textColor: "#cdd6f4"
    property color subtextColor: "#a6adc8"
    property real progress: 1.0
    property real handAngle: 0
    property bool handVisible: false
    property string mainText: "00:00"
    property string eyebrowText: ""
    property string detailText: ""

    function s(value) {
        return typeof scaleFunc === "function" ? scaleFunc(value) : value;
    }

    function alpha(color, amount) {
        return Qt.rgba(color.r, color.g, color.b, amount);
    }

    Repeater {
        model: 60

        Rectangle {
            required property int index

            width: root.s(index % 5 === 0 ? 2.2 : 1.2)
            height: root.s(index % 5 === 0 ? 7 : 4)
            radius: width / 2
            x: root.width / 2 - width / 2
            y: root.s(1)
            color: index < Math.round(Math.max(0, Math.min(1, root.progress)) * 60)
                ? root.primaryColor
                : root.alpha(root.subtextColor, 0.28)

            transform: Rotation {
                origin.x: width / 2
                origin.y: root.height / 2 - root.s(1)
                angle: index * 6
            }

            Behavior on color {
                ColorAnimation { duration: 180 }
            }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: parent.width - root.s(28)
        height: width
        radius: width / 2
        border.width: 1
        border.color: root.alpha(root.textColor, 0.08)
        gradient: Gradient {
            GradientStop {
                position: 0
                color: root.alpha(root.surfaceColor, 0.94)
            }
            GradientStop {
                position: 1
                color: root.alpha(root.secondaryColor, 0.20)
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: root.s(2)

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: text !== ""
                text: root.eyebrowText
                color: root.subtextColor
                font.family: "Noto Sans"
                font.pixelSize: root.s(8)
                font.weight: Font.Medium
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.mainText
                color: root.textColor
                font.family: "Noto Sans"
                font.pixelSize: root.s(root.mainText.length > 9 ? 19 : 23)
                font.weight: Font.Bold
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: text !== ""
                text: root.detailText
                color: root.subtextColor
                font.family: "Noto Sans"
                font.pixelSize: root.s(8)
            }
        }
    }

    Item {
        anchors.fill: parent
        visible: root.handVisible
        rotation: root.handAngle

        Behavior on rotation {
            enabled: Math.abs(root.handAngle) < 0.001
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.s(13)
            width: root.s(1.6)
            height: root.height / 2 - root.s(13)
            radius: width / 2
            color: root.primaryColor
        }
    }

    Rectangle {
        anchors.centerIn: parent
        visible: root.handVisible
        width: root.s(6)
        height: width
        radius: width / 2
        color: root.primaryColor
    }
}
