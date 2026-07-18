import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    function requestedScreen() {
        const output = Quickshell.env("ZOOMIT_OUTPUT");
        for (let index = 0; index < Quickshell.screens.length; index++) {
            if (Quickshell.screens[index].name === output)
                return Quickshell.screens[index];
        }
        return Quickshell.cursorScreen;
    }

    screen: requestedScreen()
    implicitWidth: screen.width
    implicitHeight: screen.height
    color: "black"
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "hypr-zoomit-draw"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    property color penColor: "#ff3b30"
    property real penWidth: 5
    property var strokes: []
    property var currentStroke: null
    property var pendingSegments: []
    property bool fullRedraw: true
    property bool tabHeld: false
    property int backgroundMode: 0
    property bool closing: false
    property string statusText: "DRAW  •  drag to ink  •  right-click / Esc to close"

    function setStatus(message) {
        statusText = message;
        statusOpacity.restart();
    }

    function setColor(value, name) {
        penColor = value;
        setStatus(name.toUpperCase() + " PEN  •  " + Math.round(penWidth) + " px");
    }

    function requestFullRedraw() {
        fullRedraw = true;
        pendingSegments = [];
        ink.requestPaint();
    }

    function undo() {
        if (currentStroke !== null)
            currentStroke = null;
        if (strokes.length > 0) {
            const copy = strokes.slice();
            copy.pop();
            strokes = copy;
            requestFullRedraw();
            setStatus("UNDO");
        }
    }

    function clearInk() {
        strokes = [];
        currentStroke = null;
        requestFullRedraw();
        setStatus("INK CLEARED");
    }

    function closeAnimated() {
        if (closing)
            return;
        closing = true;
        exitAnimation.start();
    }

    function drawStroke(context, stroke) {
        if (!stroke || !stroke.points || stroke.points.length === 0)
            return;
        context.strokeStyle = stroke.color;
        context.fillStyle = stroke.color;
        context.lineWidth = stroke.width;
        context.lineCap = "round";
        context.lineJoin = "round";

        const points = stroke.points;
        if (stroke.kind === "free") {
            if (points.length === 1) {
                context.beginPath();
                context.arc(points[0].x, points[0].y, stroke.width / 2, 0, Math.PI * 2);
                context.fill();
                return;
            }
            context.beginPath();
            context.moveTo(points[0].x, points[0].y);
            for (let index = 1; index < points.length; index++)
                context.lineTo(points[index].x, points[index].y);
            context.stroke();
            return;
        }

        const first = points[0];
        const last = points[points.length - 1];
        if (stroke.kind === "rectangle") {
            context.strokeRect(first.x, first.y, last.x - first.x, last.y - first.y);
        } else if (stroke.kind === "ellipse") {
            const centerX = (first.x + last.x) / 2;
            const centerY = (first.y + last.y) / 2;
            const radiusX = Math.max(1, Math.abs(last.x - first.x) / 2);
            const radiusY = Math.max(1, Math.abs(last.y - first.y) / 2);
            context.save();
            context.translate(centerX, centerY);
            context.scale(radiusX, radiusY);
            context.beginPath();
            context.arc(0, 0, 1, 0, Math.PI * 2);
            context.restore();
            context.stroke();
        } else {
            context.beginPath();
            context.moveTo(first.x, first.y);
            context.lineTo(last.x, last.y);
            context.stroke();
            if (stroke.kind === "arrow") {
                const angle = Math.atan2(last.y - first.y, last.x - first.x);
                const head = Math.max(14, stroke.width * 3.2);
                context.beginPath();
                context.moveTo(last.x, last.y);
                context.lineTo(last.x - head * Math.cos(angle - Math.PI / 6), last.y - head * Math.sin(angle - Math.PI / 6));
                context.moveTo(last.x, last.y);
                context.lineTo(last.x - head * Math.cos(angle + Math.PI / 6), last.y - head * Math.sin(angle + Math.PI / 6));
                context.stroke();
            }
        }
    }

    Item {
        id: scene
        anchors.fill: parent
        opacity: 0

        Image {
            anchors.fill: parent
            source: "file://" + Quickshell.env("ZOOMIT_SCREENSHOT")
            fillMode: Image.Stretch
            cache: false
            smooth: true
            visible: root.backgroundMode === 0
        }

        Rectangle {
            anchors.fill: parent
            color: root.backgroundMode === 1 ? "white" : "black"
            visible: root.backgroundMode !== 0
            Behavior on color { ColorAnimation { duration: 140 } }
        }

        Canvas {
            id: ink
            anchors.fill: parent
            renderStrategy: Canvas.Threaded
            antialiasing: true

            onPaint: {
                const context = getContext("2d");
                if (root.fullRedraw) {
                    context.reset();
                    context.clearRect(0, 0, width, height);
                    for (let index = 0; index < root.strokes.length; index++)
                        root.drawStroke(context, root.strokes[index]);
                    root.fullRedraw = false;
                } else {
                    for (let index = 0; index < root.pendingSegments.length; index++)
                        root.drawStroke(context, root.pendingSegments[index]);
                }
                root.pendingSegments = [];
            }
        }

        Canvas {
            id: preview
            anchors.fill: parent
            renderStrategy: Canvas.Threaded
            antialiasing: true
            onPaint: {
                const context = getContext("2d");
                context.reset();
                context.clearRect(0, 0, width, height);
                if (root.currentStroke !== null && root.currentStroke.kind !== "free")
                    root.drawStroke(context, root.currentStroke);
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            cursorShape: Qt.CrossCursor

            onPressed: mouse => {
                if (mouse.button === Qt.RightButton) {
                    root.closeAnimated();
                    return;
                }
                let kind = "free";
                if ((mouse.modifiers & Qt.ControlModifier) && (mouse.modifiers & Qt.ShiftModifier))
                    kind = "arrow";
                else if (root.tabHeld || (mouse.modifiers & Qt.AltModifier))
                    kind = "ellipse";
                else if (mouse.modifiers & Qt.ControlModifier)
                    kind = "rectangle";
                else if (mouse.modifiers & Qt.ShiftModifier)
                    kind = "line";
                root.currentStroke = {
                    "kind": kind,
                    "color": root.penColor,
                    "width": root.penWidth,
                    "points": [{"x": mouse.x, "y": mouse.y}]
                };
                if (kind === "free") {
                    root.pendingSegments = [root.currentStroke];
                    ink.requestPaint();
                } else {
                    preview.requestPaint();
                }
            }

            onPositionChanged: mouse => {
                if (!(mouse.buttons & Qt.LeftButton) || root.currentStroke === null)
                    return;
                const points = root.currentStroke.points;
                const previous = points[points.length - 1];
                const next = {"x": mouse.x, "y": mouse.y};
                if (root.currentStroke.kind === "free") {
                    if (Math.abs(next.x - previous.x) + Math.abs(next.y - previous.y) < 1.5)
                        return;
                    points.push(next);
                    root.pendingSegments.push({
                        "kind": "free",
                        "color": root.currentStroke.color,
                        "width": root.currentStroke.width,
                        "points": [previous, next]
                    });
                    ink.requestPaint();
                } else {
                    root.currentStroke.points = [points[0], next];
                    preview.requestPaint();
                }
            }

            onReleased: mouse => {
                if (mouse.button !== Qt.LeftButton || root.currentStroke === null)
                    return;
                const copy = root.strokes.slice();
                copy.push(root.currentStroke);
                root.strokes = copy;
                const wasShape = root.currentStroke.kind !== "free";
                root.currentStroke = null;
                if (wasShape) {
                    preview.requestPaint();
                    root.requestFullRedraw();
                }
            }

            onWheel: wheel => {
                if (wheel.modifiers & Qt.ControlModifier) {
                    const direction = wheel.angleDelta.y > 0 ? 1 : -1;
                    root.penWidth = Math.max(2, Math.min(40, root.penWidth + direction));
                    root.setStatus("PEN WIDTH  •  " + Math.round(root.penWidth) + " px");
                    wheel.accepted = true;
                }
            }
        }

        Item {
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.closeAnimated();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Tab) {
                    root.tabHeld = true;
                    root.setStatus("ELLIPSE  •  hold Tab and drag");
                    event.accepted = true;
                } else if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier)) {
                    root.undo();
                    event.accepted = true;
                } else if (event.key === Qt.Key_E || event.key === Qt.Key_Delete) {
                    root.clearInk();
                    event.accepted = true;
                } else if (event.key === Qt.Key_R) {
                    root.setColor("#ff3b30", "red");
                } else if (event.key === Qt.Key_G) {
                    root.setColor("#34c759", "green");
                } else if (event.key === Qt.Key_B) {
                    root.setColor("#0a84ff", "blue");
                } else if (event.key === Qt.Key_Y) {
                    root.setColor("#ffd60a", "yellow");
                } else if (event.key === Qt.Key_O) {
                    root.setColor("#ff9f0a", "orange");
                } else if (event.key === Qt.Key_P) {
                    root.setColor("#ff2d9a", "pink");
                } else if (event.key === Qt.Key_W) {
                    root.backgroundMode = 1;
                    root.setStatus("WHITEBOARD");
                } else if (event.key === Qt.Key_K) {
                    root.backgroundMode = 2;
                    root.setStatus("BLACKBOARD");
                }
            }
            Keys.onReleased: event => {
                if (event.key === Qt.Key_Tab) {
                    root.tabHeld = false;
                    event.accepted = true;
                }
            }
        }

        Rectangle {
            id: hud
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 28
            width: hudRow.implicitWidth + 34
            height: 42
            radius: 21
            color: "#d91b1b1f"
            border.color: "#44ffffff"
            border.width: 1
            opacity: 0.94

            Row {
                id: hudRow
                anchors.centerIn: parent
                spacing: 11
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(9, root.penWidth + 3)
                    height: width
                    radius: width / 2
                    color: root.penColor
                    border.color: "white"
                    border.width: 1
                    Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.statusText
                    color: "white"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }

            SequentialAnimation {
                id: statusOpacity
                PropertyAnimation { target: hud; property: "opacity"; to: 1; duration: 90 }
                PauseAnimation { duration: 1700 }
                PropertyAnimation { target: hud; property: "opacity"; to: 0.72; duration: 260 }
            }
        }
    }

    NumberAnimation {
        id: enterAnimation
        target: scene
        property: "opacity"
        from: 0
        to: 1
        duration: 150
        easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: exitAnimation
        NumberAnimation {
            target: scene
            property: "opacity"
            to: 0
            duration: 130
            easing.type: Easing.InCubic
        }
        ScriptAction { script: Qt.quit() }
    }

    Component.onCompleted: enterAnimation.start()
}
