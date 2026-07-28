import QtQuick

Item {
    id: root

    property bool effectEnabled: true
    property bool active: false
    property bool pressed: false
    property real cornerRadius: 10
    property real outlineWidth: 3.4
    property var palette: ["#89b4fa", "#cba6f7", "#f5c2e7", "#fab387", "#94e2d5"]
    property color pressColor: "#585b70"

    property real gradientPhase: 0
    property real outlineProgress: 0.0
    property bool syntheticPressed: false
    property bool pointerActivationPending: false

    readonly property bool effectivePressed: effectEnabled && (pressed || syntheticPressed)
    readonly property real visualScale: effectivePressed ? 0.91 : 1.0
    readonly property real pressOpacity: effectivePressed ? 0.58 : 0.0

    visible: effectEnabled && (active || effectivePressed || outlineProgress > 0.001)
    z: 100

    onPressedChanged: {
        if (pressed) {
            pointerActivationPending = true;
            pointerActivationGuard.stop();
            shortcutPress.stop();
            syntheticPressed = false;
        } else if (pointerActivationPending) {
            pointerActivationGuard.restart();
        }
    }

    onActiveChanged: {
        if (!effectEnabled) return;
        if (pointerActivationPending) {
            pointerActivationPending = false;
            pointerActivationGuard.stop();
        } else {
            shortcutPress.restart();
        }
        if (active) {
            outlineExit.stop();
            outlineEnter.restart();
        } else {
            outlineEnter.stop();
            outlineExit.restart();
        }
    }

    onEffectEnabledChanged: {
        if (!effectEnabled) {
            shortcutPress.stop();
            outlineEnter.stop();
            outlineExit.stop();
            pointerActivationGuard.stop();
            syntheticPressed = false;
            pointerActivationPending = false;
            outlineProgress = 0;
        } else if (active) {
            shortcutPress.restart();
            outlineEnter.restart();
        }
    }

    SequentialAnimation {
        id: shortcutPress

        PropertyAction {
            target: root
            property: "syntheticPressed"
            value: true
        }
        PauseAnimation { duration: 140 }
        PropertyAction {
            target: root
            property: "syntheticPressed"
            value: false
        }
    }

    Timer {
        id: pointerActivationGuard
        interval: 700
        onTriggered: root.pointerActivationPending = false
    }

    NumberAnimation {
        id: outlineEnter
        target: root
        property: "outlineProgress"
        to: 1.0
        duration: 180
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: outlineExit
        target: root
        property: "outlineProgress"
        to: 0.0
        duration: 460
        easing.type: Easing.InOutCubic
    }

    Component.onCompleted: {
        outlineProgress = effectEnabled && active ? 1.0 : 0.0;
    }

    NumberAnimation on gradientPhase {
        from: 0
        to: 1
        duration: 3600
        loops: Animation.Infinite
        running: root.effectEnabled && root.active
    }

    Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        color: root.pressColor
        opacity: root.pressOpacity

        Behavior on opacity {
            NumberAnimation {
                duration: root.effectivePressed ? 70 : 210
                easing.type: root.effectivePressed ? Easing.OutCubic : Easing.OutExpo
            }
        }
    }

    Canvas {
        id: outlineCanvas
        anchors.fill: parent
        visible: opacity > 0.001
        opacity: root.effectEnabled ? Math.min(1.0, root.outlineProgress * 2.5) : 0.0

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const animatedOutlineWidth = root.outlineWidth * root.outlineProgress;
            if (width <= 1 || height <= 1 || animatedOutlineWidth <= 0.01) return;

            const inset = Math.max(1, animatedOutlineWidth / 2 + 0.5);
            const left = inset;
            const top = inset;
            const right = width - inset;
            const bottom = height - inset;
            const maxRadius = Math.max(0, Math.min((right - left) / 2, (bottom - top) / 2));
            const radius = Math.max(0, Math.min(root.cornerRadius - inset / 2, maxRadius));
            const horizontal = Math.max(0, right - left - 2 * radius);
            const vertical = Math.max(0, bottom - top - 2 * radius);
            const arcLength = Math.PI * radius / 2;
            const perimeter = 2 * horizontal + 2 * vertical + 4 * arcLength;
            if (perimeter <= 0) return;

            function pointAt(distance) {
                let d = ((distance % perimeter) + perimeter) % perimeter;
                if (d <= horizontal) return { x: left + radius + d, y: top };
                d -= horizontal;
                if (d <= arcLength) {
                    const angle = -Math.PI / 2 + (d / arcLength) * Math.PI / 2;
                    return { x: right - radius + Math.cos(angle) * radius, y: top + radius + Math.sin(angle) * radius };
                }
                d -= arcLength;
                if (d <= vertical) return { x: right, y: top + radius + d };
                d -= vertical;
                if (d <= arcLength) {
                    const angle = (d / arcLength) * Math.PI / 2;
                    return { x: right - radius + Math.cos(angle) * radius, y: bottom - radius + Math.sin(angle) * radius };
                }
                d -= arcLength;
                if (d <= horizontal) return { x: right - radius - d, y: bottom };
                d -= horizontal;
                if (d <= arcLength) {
                    const angle = Math.PI / 2 + (d / arcLength) * Math.PI / 2;
                    return { x: left + radius + Math.cos(angle) * radius, y: bottom - radius + Math.sin(angle) * radius };
                }
                d -= arcLength;
                if (d <= vertical) return { x: left, y: bottom - radius - d };
                d -= vertical;
                const angle = Math.PI + (d / arcLength) * Math.PI / 2;
                return { x: left + radius + Math.cos(angle) * radius, y: top + radius + Math.sin(angle) * radius };
            }

            function colorAt(position) {
                const colors = root.palette && root.palette.length > 0
                    ? root.palette
                    : ["#89b4fa", "#cba6f7", "#f5c2e7", "#fab387", "#94e2d5"];
                const t = ((position + root.gradientPhase) % 1 + 1) % 1;
                const scaled = t * colors.length;
                const index = Math.floor(scaled) % colors.length;
                const next = (index + 1) % colors.length;
                const mix = scaled - Math.floor(scaled);
                const a = colors[index];
                const b = colors[next];
                return Qt.rgba(
                    a.r + (b.r - a.r) * mix,
                    a.g + (b.g - a.g) * mix,
                    a.b + (b.b - a.b) * mix,
                    1.0
                );
            }

            const segments = Math.max(80, Math.min(180, Math.round(perimeter * 1.8)));
            ctx.lineWidth = animatedOutlineWidth;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";

            for (let i = 0; i < segments; ++i) {
                const start = pointAt((i / segments) * perimeter);
                const end = pointAt(((i + 1.15) / segments) * perimeter);
                ctx.beginPath();
                ctx.moveTo(start.x, start.y);
                ctx.lineTo(end.x, end.y);
                ctx.strokeStyle = colorAt((i + 0.5) / segments);
                ctx.stroke();
            }
        }

        Connections {
            target: root
            function onGradientPhaseChanged() { outlineCanvas.requestPaint(); }
            function onPaletteChanged() { outlineCanvas.requestPaint(); }
            function onCornerRadiusChanged() { outlineCanvas.requestPaint(); }
            function onOutlineWidthChanged() { outlineCanvas.requestPaint(); }
            function onOutlineProgressChanged() { outlineCanvas.requestPaint(); }
            function onActiveChanged() { outlineCanvas.requestPaint(); }
        }
    }
}
