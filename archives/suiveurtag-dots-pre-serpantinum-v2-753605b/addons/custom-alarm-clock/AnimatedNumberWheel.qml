import QtQuick
import QtQuick.Controls

Item {
    id: root

    property var scaleFunc: function(value) {
        return value;
    }
    property color textColor: "#cdd6f4"
    property color subtextColor: "#a6adc8"
    property color accentColor: "#cba6f7"
    property string label: ""
    property int value: 0
    property int maximum: 59
    property bool selected: false
    property bool ready: false
    property bool syncing: false
    property int lastIndex: 0
    property bool programActive: false
    property int programDirection: 1
    property int programTargetIndex: 0
    property int queuedSteps: 0
    property real programProgress: 0
    property bool glideStep: false
    property bool glideEnding: false

    signal deltaRequested(int delta)
    signal selectedRequested()

    function s(amount) {
        return typeof scaleFunc === "function" ? scaleFunc(amount) : amount;
    }

    function alpha(color, amount) {
        return Qt.rgba(color.r, color.g, color.b, amount);
    }

    function mixColor(fromColor, toColor, amount) {
        const progress = Math.max(0, Math.min(1, amount));
        return Qt.rgba(fromColor.r + (toColor.r - fromColor.r) * progress, fromColor.g + (toColor.g - fromColor.g) * progress, fromColor.b + (toColor.b - fromColor.b) * progress, fromColor.a + (toColor.a - fromColor.a) * progress);
    }

    function wrapped(base, offset) {
        const range = maximum + 1;
        return (base + offset + range) % range;
    }

    function signedDelta(fromIndex, toIndex) {
        const range = maximum + 1;
        let delta = toIndex - fromIndex;
        if (delta > range / 2)
            delta -= range;

        if (delta < -range / 2)
            delta += range;

        return delta;
    }

    function syncToValue() {
        if (!ready || programActive || wheel.currentIndex === value)
            return ;

        syncing = true;
        wheel.positionViewAtIndex(value, Tumbler.Center);
        lastIndex = value;
        syncing = false;
    }

    function startWheelStep(stepDirection, isGlideStep, isGlideEnding) {
        programDirection = stepDirection < 0 ? -1 : 1;
        programTargetIndex = wrapped(wheel.currentIndex, programDirection);
        programProgress = 0;
        glideStep = isGlideStep === true;
        glideEnding = isGlideEnding === true;
        programActive = true;
        wheelStepAnimation.restart();
    }

    function requestStep(stepDirection) {
        const direction = stepDirection < 0 ? -1 : 1;
        selectedRequested();
        if (programActive || wheelStepAnimation.running) {
            queuedSteps = Math.max(-8, Math.min(8, queuedSteps + direction));
            if (glideEnding && queuedSteps !== 0)
                glideEnding = false;

            return ;
        }
        startWheelStep(direction, false, false);
    }

    width: s(72)
    height: s(124)
    clip: true
    onValueChanged: syncToValue()
    Component.onCompleted: {
        syncing = true;
        wheel.positionViewAtIndex(value, Tumbler.Center);
        lastIndex = value;
        syncing = false;
        ready = true;
    }

    Text {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.label
        color: root.alpha(root.subtextColor, 0.78)
        font.family: "Noto Sans"
        font.pixelSize: root.s(8)
        z: 3
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: wheel.verticalCenter
        width: root.s(62)
        height: root.s(42)
        radius: root.s(15)
        color: root.alpha(root.accentColor, root.selected ? 0.11 : 0)
        border.width: root.selected ? 1 : 0
        border.color: root.alpha(root.accentColor, 0.24)
        z: 0

        Behavior on color {
            ColorAnimation {
                duration: 140
            }

        }

    }

    Tumbler {
        id: wheel

        anchors.top: parent.top
        anchors.topMargin: root.s(18)
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        model: root.maximum + 1
        visibleItemCount: 3
        wrap: true
        flickDeceleration: 300
        padding: 0
        background: null
        z: 1
        onCurrentIndexChanged: {
            if (!root.ready || root.syncing || root.programActive || currentIndex < 0)
                return ;

            root.selectedRequested();
            const delta = root.signedDelta(root.lastIndex, currentIndex);
            root.lastIndex = currentIndex;
            if (delta !== 0)
                root.deltaRequested(delta);

        }
        onMovingChanged: {
            if (!moving && root.ready && !root.programActive)
                root.syncToValue();

        }

        transform: Translate {
            y: -root.programDirection * root.programProgress * (wheel.height / wheel.visibleItemCount)
        }

        delegate: Text {
            required property int index
            required property var modelData
            readonly property real displacement: Tumbler.displacement
            readonly property real visualDisplacement: displacement - (root.programActive ? root.programDirection * root.programProgress : 0)
            readonly property real distance: Math.min(1.5, Math.abs(visualDisplacement))
            readonly property real centerWeight: Math.max(0, Math.min(1, 1 - distance / 0.86))
            readonly property color idleColor: root.alpha(root.subtextColor, 0.32)
            readonly property color activeColor: root.selected ? root.accentColor : root.textColor

            text: String(modelData).padStart(2, "0")
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: root.mixColor(idleColor, activeColor, centerWeight)
            opacity: 0.25 + centerWeight * 0.75
            scale: 0.76 + centerWeight * 0.24
            font.family: "Noto Sans"
            font.pixelSize: root.s(31)
            font.weight: Font.Bold
        }

    }

    MouseArea {
        anchors.fill: wheel
        acceptedButtons: Qt.NoButton
        scrollGestureEnabled: true
        z: 2
        onWheel: (event) => {
            const amount = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y;
            if (amount !== 0)
                root.requestStep(amount > 0 ? -1 : 1);

            event.accepted = true;
        }
    }

    NumberAnimation {
        id: wheelStepAnimation

        target: root
        property: "programProgress"
        from: 0
        to: 1
        duration: root.glideStep ? (root.glideEnding ? 108 : 64) : 108
        easing.type: root.glideStep && !root.glideEnding ? Easing.Linear : Easing.OutSine
        onFinished: {
            root.syncing = true;
            wheel.positionViewAtIndex(root.programTargetIndex, Tumbler.Center);
            root.lastIndex = root.programTargetIndex;
            root.syncing = false;
            root.programProgress = 0;
            root.programActive = false;
            root.deltaRequested(root.programDirection);
            if (root.queuedSteps !== 0)
                queuedStepTimer.restart();

        }
    }

    Timer {
        id: queuedStepTimer

        interval: 0
        repeat: false
        onTriggered: {
            if (root.queuedSteps === 0)
                return ;

            const direction = root.queuedSteps > 0 ? 1 : -1;
            root.queuedSteps -= direction;
            root.startWheelStep(direction, true, root.queuedSteps === 0);
        }
    }

}
