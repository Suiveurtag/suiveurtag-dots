import QtQuick
import QtQuick.Effects

Item {
    id: root

    property var scaleFunc: function(value) { return value; }
    property int activeMode: 0
    property bool animate: true
    property color baseColor: "#181825"
    property color primaryColor: "#cba6f7"
    property color secondaryColor: "#89b4fa"
    property color tertiaryColor: "#f5c2e7"
    property color breakColor: "#a6e3a1"

    property real phase: 0
    property real modeShift: activeMode

    function s(value) {
        return typeof scaleFunc === "function" ? scaleFunc(value) : value;
    }

    function alpha(color, amount) {
        return Qt.rgba(color.r, color.g, color.b, amount);
    }

    function mix(first, second, amount) {
        return Qt.rgba(
            first.r + (second.r - first.r) * amount,
            first.g + (second.g - first.g) * amount,
            first.b + (second.b - first.b) * amount,
            1
        );
    }

    function colorForMode(mode, secondary) {
        if (mode < 0.5)
            return secondary ? root.tertiaryColor : root.secondaryColor;
        if (mode < 1.5)
            return secondary ? root.primaryColor : root.secondaryColor;
        if (mode < 2.5)
            return secondary ? root.breakColor : root.primaryColor;
        return secondary ? root.primaryColor : root.tertiaryColor;
    }

    clip: true

    Behavior on modeShift {
        NumberAnimation {
            duration: 720
            easing.type: Easing.InOutCubic
        }
    }

    NumberAnimation on phase {
        from: 0
        to: Math.PI * 2
        duration: 14500
        loops: Animation.Infinite
        running: root.animate && root.visible
    }

    Rectangle {
        anchors.fill: parent
        color: root.mix(root.baseColor, "#000000", 0.62)
    }

    Rectangle {
        id: upperBlob

        width: parent.width * 0.46
        height: parent.height * 1.06
        radius: width / 2
        x: parent.width * (0.20 + 0.055 * Math.sin(root.phase + root.modeShift * 0.8))
        y: -parent.height * (0.29 + 0.035 * root.modeShift)
            + parent.height * 0.055 * Math.cos(root.phase * 0.72)
        rotation: -8 + Math.sin(root.phase * 0.55) * 5
        color: root.alpha(root.colorForMode(root.modeShift, false), 0.32)
        opacity: 0.88

        Behavior on color {
            ColorAnimation {
                duration: 780
                easing.type: Easing.InOutCubic
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 72
        }
    }

    Rectangle {
        id: lowerBlob

        width: parent.width * 0.54
        height: parent.height * 1.12
        radius: width / 2
        x: parent.width * (0.40 + 0.07 * Math.cos(root.phase * 0.81 + root.modeShift))
        y: parent.height * (0.28 - 0.055 * Math.sin(root.modeShift * 1.2))
            + parent.height * 0.06 * Math.sin(root.phase * 0.64)
        rotation: 11 + Math.cos(root.phase * 0.48) * 6
        color: root.alpha(root.colorForMode(root.modeShift, true), 0.36)
        opacity: 0.92

        Behavior on color {
            ColorAnimation {
                duration: 780
                easing.type: Easing.InOutCubic
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 78
        }
    }

    Rectangle {
        width: parent.width * 0.34
        height: parent.height * 0.74
        radius: width / 2
        x: parent.width * (0.06 + 0.055 * Math.sin(root.phase * 0.92 + 2.2))
        y: parent.height * (0.16 + 0.08 * Math.cos(root.phase * 0.58 + 0.6))
        rotation: -18
        color: root.alpha(root.secondaryColor, 0.22)
        opacity: 0.72

        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 64
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.alpha(root.baseColor, 0.12)
    }
}
