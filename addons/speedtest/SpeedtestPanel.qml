import QtQuick
import QtQuick.Layouts

Rectangle {
    id: panel

    required property var rootWindow

    readonly property bool shown: rootWindow.showSpeedtestPanel
    readonly property bool running: rootWindow.speedtestRunning
    readonly property string phase: rootWindow.speedtestPhase
    readonly property color backgroundColor: rootWindow.mantle
    readonly property color deepBackgroundColor: rootWindow.crust
    readonly property color cardColor: rootWindow.surface0
    readonly property color trackColor: rootWindow.surface1
    readonly property color softTrackColor: rootWindow.surface2
    readonly property color primaryTextColor: rootWindow.text
    readonly property color secondaryTextColor: rootWindow.subtext0
    readonly property color mutedTextColor: rootWindow.overlay0
    readonly property color downloadColor: "#00d7f2"
    readonly property color downloadSecondaryColor: rootWindow.sapphire
    readonly property color uploadColor: rootWindow.mauve
    readonly property color uploadSecondaryColor: rootWindow.pink
    readonly property color latencyColor: rootWindow.peach
    readonly property color phaseAccent: phase === "upload" ? uploadColor
                                                          : (phase === "latency" ? latencyColor : downloadColor)
    readonly property color phaseAccentSecondary: phase === "upload" ? uploadSecondaryColor
                                                                   : (phase === "latency" ? rootWindow.maroon : downloadSecondaryColor)

    function s(value) {
        return rootWindow.s(value);
    }

    function speedFraction(value) {
        const speed = Math.max(0, Number(value) || 0);
        const stops = [0, 5, 10, 50, 100, 250, 500, 750, 1000];
        if (speed >= stops[stops.length - 1]) return 1;
        for (let index = 1; index < stops.length; index++) {
            if (speed <= stops[index]) {
                const local = (speed - stops[index - 1]) / (stops[index] - stops[index - 1]);
                return ((index - 1) + local) / (stops.length - 1);
            }
        }
        return 0;
    }

    function statusTitle() {
        if (rootWindow.speedtestState === "error") return "TEST FAILED";
        if (phase === "latency") return "MEASURING PING";
        if (phase === "download") return "DOWNLOAD";
        if (phase === "upload") return "UPLOAD";
        if (phase === "complete") return "RESULT";
        return "READY";
    }

    radius: s(26)
    z: 85
    visible: opacity > 0.01
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.965
    color: Qt.rgba(backgroundColor.r, backgroundColor.g, backgroundColor.b, 0.985)
    border.color: Qt.rgba(softTrackColor.r, softTrackColor.g, softTrackColor.b, 0.72)
    border.width: 1
    clip: true

    Behavior on opacity {
        NumberAnimation { duration: 360; easing.type: Easing.OutQuint }
    }
    Behavior on scale {
        NumberAnimation { duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.05 }
    }
    Behavior on border.color {
        ColorAnimation { duration: 700; easing.type: Easing.InOutCubic }
    }

    Rectangle {
        anchors.fill: parent
        color: deepBackgroundColor
        opacity: 0.28
    }

    Item {
        id: ambientLayer
        anchors.fill: parent
        opacity: panel.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 800 } }

        Rectangle {
            width: panel.s(420)
            height: width
            radius: width / 2
            x: -width * 0.48
            y: -height * 0.54
            color: panel.downloadColor
            opacity: panel.phase === "upload" ? 0.045 : 0.09
            Behavior on color { ColorAnimation { duration: 900 } }
            Behavior on opacity { NumberAnimation { duration: 900 } }
        }

        Rectangle {
            width: panel.s(390)
            height: width
            radius: width / 2
            x: parent.width - width * 0.52
            y: parent.height - height * 0.44
            color: panel.uploadColor
            opacity: panel.phase === "upload" ? 0.11 : 0.05
            Behavior on color { ColorAnimation { duration: 900 } }
            Behavior on opacity { NumberAnimation { duration: 900 } }
        }

        Canvas {
            anchors.fill: parent
            opacity: 0.16
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.strokeStyle = String(panel.softTrackColor);
                ctx.lineWidth = Math.max(1, panel.s(1));
                const gap = panel.s(42);
                for (let x = -height; x < width + height; x += gap) {
                    ctx.beginPath();
                    ctx.moveTo(x, 0);
                    ctx.lineTo(x + height, height);
                    ctx.stroke();
                }
            }
        }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: s(3)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: panel.downloadColor }
            GradientStop { position: 0.5; color: panel.phaseAccent }
            GradientStop { position: 1; color: panel.uploadColor }
        }
    }

    RowLayout {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: panel.s(18)
        anchors.leftMargin: panel.s(22)
        anchors.rightMargin: panel.s(18)
        height: panel.s(44)
        spacing: panel.s(12)

        Rectangle {
            Layout.preferredWidth: panel.s(42)
            Layout.preferredHeight: panel.s(42)
            radius: width / 2
            color: Qt.rgba(panel.phaseAccent.r, panel.phaseAccent.g, panel.phaseAccent.b, 0.13)
            border.color: Qt.rgba(panel.phaseAccent.r, panel.phaseAccent.g, panel.phaseAccent.b, 0.48)
            border.width: 1
            Behavior on color { ColorAnimation { duration: 650 } }
            Behavior on border.color { ColorAnimation { duration: 650 } }

            Image {
                anchors.centerIn: parent
                width: panel.s(23)
                height: width
                source: Qt.resolvedUrl("speed-alt-svgrepo-com.svg")
                sourceSize: Qt.size(64, 64)
                fillMode: Image.PreserveAspectFit
                smooth: true
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                Layout.fillWidth: true
                text: "SPEEDTEST"
                color: panel.primaryTextColor
                font.family: "JetBrains Mono"
                font.weight: Font.Black
                font.letterSpacing: panel.s(1.6)
                font.pixelSize: panel.s(17)
            }

            Text {
                Layout.fillWidth: true
                text: (panel.rootWindow.speedtestServer || "Cloudflare") + "  •  AUTO SERVER"
                color: panel.mutedTextColor
                font.family: "JetBrains Mono"
                font.weight: Font.Medium
                font.letterSpacing: panel.s(0.45)
                font.pixelSize: panel.s(9)
                elide: Text.ElideRight
            }
        }

        Rectangle {
            Layout.preferredWidth: statusText.implicitWidth + panel.s(22)
            Layout.preferredHeight: panel.s(30)
            radius: height / 2
            color: Qt.rgba(panel.phaseAccent.r, panel.phaseAccent.g, panel.phaseAccent.b, 0.1)
            border.color: Qt.rgba(panel.phaseAccent.r, panel.phaseAccent.g, panel.phaseAccent.b, 0.34)
            border.width: 1
            Behavior on color { ColorAnimation { duration: 550 } }
            Behavior on border.color { ColorAnimation { duration: 550 } }

            Row {
                anchors.centerIn: parent
                spacing: panel.s(7)

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: panel.s(6)
                    height: width
                    radius: width / 2
                    color: panel.rootWindow.speedtestState === "error" ? panel.rootWindow.red : panel.phaseAccent

                    SequentialAnimation on opacity {
                        running: panel.running
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 620; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 620; easing.type: Easing.InOutSine }
                    }
                }

                Text {
                    id: statusText
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.statusTitle()
                    color: panel.primaryTextColor
                    font.family: "JetBrains Mono"
                    font.weight: Font.Bold
                    font.letterSpacing: panel.s(0.7)
                    font.pixelSize: panel.s(9)
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: panel.s(34)
            Layout.preferredHeight: panel.s(34)
            radius: width / 2
            color: closeArea.containsMouse ? panel.cardColor : "transparent"
            border.color: closeArea.containsMouse ? panel.softTrackColor : panel.trackColor
            border.width: 1
            scale: closeArea.pressed ? 0.9 : 1
            Behavior on color { ColorAnimation { duration: 180 } }
            Behavior on border.color { ColorAnimation { duration: 180 } }
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

            Text {
                anchors.centerIn: parent
                text: "󰅖"
                color: panel.primaryTextColor
                font.family: "Iosevka Nerd Font"
                font.pixelSize: panel.s(15)
            }

            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.rootWindow.showSpeedtestPanel = false
            }
        }
    }

    Row {
        id: metricsRow
        anchors.top: header.bottom
        anchors.topMargin: panel.s(10)
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - panel.s(44)
        height: panel.s(58)
        spacing: panel.s(8)

        Repeater {
            model: [
                {
                    label: "PING",
                    value: panel.rootWindow.speedtestLatency !== "" ? panel.rootWindow.speedtestLatency : "—",
                    unit: "ms",
                    icon: "󰔟",
                    accent: panel.latencyColor,
                    active: panel.phase === "latency"
                },
                {
                    label: "DOWNLOAD",
                    value: panel.phase === "download" && panel.running
                           ? speedGauge.indicatedMbps.toFixed(1)
                           : (panel.rootWindow.speedtestDownload !== "" ? panel.rootWindow.speedtestDownload : "—"),
                    unit: "Mbps",
                    icon: "󰇚",
                    accent: panel.downloadColor,
                    active: panel.phase === "download"
                },
                {
                    label: "UPLOAD",
                    value: panel.phase === "upload" && panel.running
                           ? speedGauge.indicatedMbps.toFixed(1)
                           : (panel.rootWindow.speedtestUpload !== "" ? panel.rootWindow.speedtestUpload : "—"),
                    unit: "Mbps",
                    icon: "󰕒",
                    accent: panel.uploadColor,
                    active: panel.phase === "upload"
                }
            ]

            delegate: Rectangle {
                required property var modelData

                width: (metricsRow.width - metricsRow.spacing * 2) / 3
                height: metricsRow.height
                radius: panel.s(13)
                color: modelData.active
                       ? Qt.rgba(modelData.accent.r, modelData.accent.g, modelData.accent.b, 0.11)
                       : Qt.rgba(panel.cardColor.r, panel.cardColor.g, panel.cardColor.b, 0.52)
                border.color: modelData.active
                              ? Qt.rgba(modelData.accent.r, modelData.accent.g, modelData.accent.b, 0.52)
                              : Qt.rgba(panel.softTrackColor.r, panel.softTrackColor.g, panel.softTrackColor.b, 0.34)
                border.width: 1
                Behavior on color { ColorAnimation { duration: 480; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: 480; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: modelData.active ? panel.s(3) : 0
                    radius: width / 2
                    color: modelData.accent
                    Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutExpo } }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: panel.s(13)
                    anchors.rightMargin: panel.s(11)
                    spacing: panel.s(8)

                    Text {
                        text: modelData.icon
                        color: modelData.accent
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: panel.s(17)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            text: modelData.label + "  " + modelData.unit
                            color: modelData.active ? modelData.accent : panel.mutedTextColor
                            font.family: "JetBrains Mono"
                            font.weight: Font.Bold
                            font.letterSpacing: panel.s(0.45)
                            font.pixelSize: panel.s(8)
                            Behavior on color { ColorAnimation { duration: 420 } }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.value
                            color: panel.primaryTextColor
                            font.family: "JetBrains Mono"
                            font.weight: Font.Black
                            font.pixelSize: panel.s(16)
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: progressTrack
        anchors.top: metricsRow.bottom
        anchors.topMargin: panel.s(9)
        anchors.horizontalCenter: parent.horizontalCenter
        width: metricsRow.width
        height: panel.s(3)
        radius: height / 2
        color: Qt.rgba(panel.trackColor.r, panel.trackColor.g, panel.trackColor.b, 0.72)

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, panel.rootWindow.speedtestProgress))
            height: parent.height
            radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: panel.downloadColor }
                GradientStop { position: 0.52; color: panel.phaseAccent }
                GradientStop { position: 1; color: panel.uploadColor }
            }
            Behavior on width {
                NumberAnimation { duration: 760; easing.type: Easing.OutQuint }
            }
        }
    }

    Item {
        id: gaugeArea
        anchors.top: progressTrack.bottom
        anchors.bottom: footer.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: panel.s(2)
        anchors.bottomMargin: panel.s(2)

        Canvas {
            id: speedGauge
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: panel.s(11)
            width: Math.max(panel.s(40), Math.min(gaugeArea.width - panel.s(60), panel.s(500)))
            height: Math.max(panel.s(40), Math.min(gaugeArea.height + panel.s(25), panel.s(330)))
            renderTarget: Canvas.FramebufferObject

            property real indicatedMbps: panel.rootWindow.speedtestVisualMbps
            property color accentValue: panel.phaseAccent
            property color accentSecondaryValue: panel.phaseAccentSecondary
            property color trackValue: panel.trackColor
            property color textValue: panel.mutedTextColor
            property real breathing: 0

            onIndicatedMbpsChanged: requestPaint()
            onAccentValueChanged: requestPaint()
            onAccentSecondaryValueChanged: requestPaint()
            onTrackValueChanged: requestPaint()
            onTextValueChanged: requestPaint()
            onBreathingChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            NumberAnimation on breathing {
                from: 0
                to: Math.PI * 2
                duration: 2100
                loops: Animation.Infinite
                running: panel.running && panel.shown
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();

                const cx = width / 2;
                const cy = height * 0.63;
                const radius = Math.max(panel.s(1), Math.min(width * 0.37, height * 0.52));
                const startAngle = Math.PI * 0.75;
                const sweep = Math.PI * 1.5;
                const fraction = panel.speedFraction(indicatedMbps);
                const needleAngle = startAngle + sweep * fraction;
                const lineWidth = panel.s(17);

                ctx.lineCap = "round";

                ctx.beginPath();
                ctx.arc(cx, cy, radius, startAngle, startAngle + sweep);
                ctx.lineWidth = lineWidth + panel.s(12);
                ctx.strokeStyle = String(accentValue);
                ctx.globalAlpha = panel.running ? 0.075 + Math.sin(breathing) * 0.018 : 0.045;
                ctx.stroke();

                ctx.beginPath();
                ctx.arc(cx, cy, radius, startAngle, startAngle + sweep);
                ctx.lineWidth = lineWidth;
                ctx.strokeStyle = String(trackValue);
                ctx.globalAlpha = 0.62;
                ctx.stroke();

                if (fraction > 0.002) {
                    const arcGradient = ctx.createLinearGradient(cx - radius, cy, cx + radius, cy);
                    arcGradient.addColorStop(0, String(accentSecondaryValue));
                    arcGradient.addColorStop(0.52, String(accentValue));
                    arcGradient.addColorStop(1, String(accentSecondaryValue));
                    ctx.beginPath();
                    ctx.arc(cx, cy, radius, startAngle, needleAngle);
                    ctx.lineWidth = lineWidth;
                    ctx.strokeStyle = arcGradient;
                    ctx.globalAlpha = 1;
                    ctx.stroke();
                }

                const labels = ["0", "5", "10", "50", "100", "250", "500", "750", "1000"];
                const tickInner = radius - panel.s(18);
                const tickOuter = radius - panel.s(7);
                const labelRadius = radius - panel.s(35);
                ctx.font = Math.round(panel.s(9)) + "px 'JetBrains Mono'";
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";

                for (let index = 0; index < labels.length; index++) {
                    const tickFraction = index / (labels.length - 1);
                    const angle = startAngle + sweep * tickFraction;
                    const cosine = Math.cos(angle);
                    const sine = Math.sin(angle);

                    ctx.beginPath();
                    ctx.moveTo(cx + cosine * tickInner, cy + sine * tickInner);
                    ctx.lineTo(cx + cosine * tickOuter, cy + sine * tickOuter);
                    ctx.lineWidth = index === 0 || index === labels.length - 1 ? panel.s(2) : panel.s(1);
                    ctx.strokeStyle = String(index / (labels.length - 1) <= fraction ? accentValue : textValue);
                    ctx.globalAlpha = index / (labels.length - 1) <= fraction ? 0.95 : 0.52;
                    ctx.stroke();

                    ctx.fillStyle = String(index / (labels.length - 1) <= fraction ? panel.primaryTextColor : textValue);
                    ctx.globalAlpha = index / (labels.length - 1) <= fraction ? 0.9 : 0.6;
                    ctx.fillText(labels[index], cx + cosine * labelRadius, cy + sine * labelRadius);
                }

                const needleLength = radius - panel.s(48);
                const tailLength = panel.s(14);
                const needleX = cx + Math.cos(needleAngle) * needleLength;
                const needleY = cy + Math.sin(needleAngle) * needleLength;
                const tailX = cx - Math.cos(needleAngle) * tailLength;
                const tailY = cy - Math.sin(needleAngle) * tailLength;

                ctx.beginPath();
                ctx.moveTo(tailX, tailY);
                ctx.lineTo(needleX, needleY);
                ctx.lineWidth = panel.s(9);
                ctx.strokeStyle = "#000000";
                ctx.globalAlpha = 0.28;
                ctx.stroke();

                const needleGradient = ctx.createLinearGradient(tailX, tailY, needleX, needleY);
                needleGradient.addColorStop(0, String(panel.primaryTextColor));
                needleGradient.addColorStop(0.72, String(accentValue));
                needleGradient.addColorStop(1, String(accentSecondaryValue));
                ctx.beginPath();
                ctx.moveTo(tailX, tailY);
                ctx.lineTo(needleX, needleY);
                ctx.lineWidth = panel.s(4);
                ctx.strokeStyle = needleGradient;
                ctx.globalAlpha = 1;
                ctx.stroke();

                ctx.beginPath();
                ctx.arc(cx, cy, panel.s(12), 0, Math.PI * 2);
                ctx.fillStyle = String(panel.deepBackgroundColor);
                ctx.globalAlpha = 1;
                ctx.fill();
                ctx.lineWidth = panel.s(4);
                ctx.strokeStyle = String(accentValue);
                ctx.stroke();

                ctx.beginPath();
                ctx.arc(cx, cy, panel.s(4), 0, Math.PI * 2);
                ctx.fillStyle = String(panel.primaryTextColor);
                ctx.fill();
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: speedGauge.y + speedGauge.height * 0.57
            spacing: -panel.s(2)

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: speedGauge.indicatedMbps.toFixed(1)
                color: panel.primaryTextColor
                font.family: "JetBrains Mono"
                font.weight: Font.Black
                font.pixelSize: panel.s(43)
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: panel.s(6)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.phase === "upload" ? "󰕒" : "󰇚"
                    color: panel.phaseAccent
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: panel.s(13)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.phase === "latency" ? "WAITING FOR PING" : "Mbps"
                    color: panel.secondaryTextColor
                    font.family: "JetBrains Mono"
                    font.weight: Font.Bold
                    font.letterSpacing: panel.s(0.7)
                    font.pixelSize: panel.s(10)
                }
            }
        }
    }

    RowLayout {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: panel.s(22)
        anchors.rightMargin: panel.s(22)
        anchors.bottomMargin: panel.s(16)
        height: panel.s(54)
        spacing: panel.s(12)

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: panel.s(14)
            color: Qt.rgba(panel.cardColor.r, panel.cardColor.g, panel.cardColor.b, 0.54)
            border.color: Qt.rgba(panel.softTrackColor.r, panel.softTrackColor.g, panel.softTrackColor.b, 0.36)
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: panel.s(13)
                anchors.rightMargin: panel.s(13)
                spacing: panel.s(10)

                Rectangle {
                    Layout.preferredWidth: panel.s(31)
                    Layout.preferredHeight: panel.s(31)
                    radius: width / 2
                    color: Qt.rgba(panel.phaseAccent.r, panel.phaseAccent.g, panel.phaseAccent.b, 0.13)

                    Text {
                        anchors.centerIn: parent
                        text: "󰒋"
                        color: panel.phaseAccent
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: panel.s(14)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        text: panel.rootWindow.speedtestServer || "Cloudflare"
                        color: panel.primaryTextColor
                        font.family: "JetBrains Mono"
                        font.weight: Font.Bold
                        font.pixelSize: panel.s(11)
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: panel.rootWindow.speedtestMessage || "Ready to test your connection"
                        color: panel.mutedTextColor
                        font.family: "JetBrains Mono"
                        font.pixelSize: panel.s(8)
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: panel.s(166)
            Layout.fillHeight: true
            radius: panel.s(14)
            opacity: panel.running ? 0.66 : 1
            scale: startArea.pressed && !panel.running ? 0.97 : 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: panel.phaseAccent }
                GradientStop { position: 1; color: panel.phaseAccentSecondary }
            }
            Behavior on opacity { NumberAnimation { duration: 240 } }
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

            Row {
                anchors.centerIn: parent
                spacing: panel.s(8)

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: panel.s(18)
                    height: width

                    Image {
                        anchors.fill: parent
                        visible: panel.running
                        source: Qt.resolvedUrl("loading-svgrepo-com.svg")
                        sourceSize: Qt.size(64, 64)
                        fillMode: Image.PreserveAspectFit
                        smooth: true

                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 1150
                            loops: Animation.Infinite
                            running: panel.running
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !panel.running
                        text: "󰑐"
                        color: panel.deepBackgroundColor
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: panel.s(17)
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.running ? "TESTING" : (panel.rootWindow.speedtestState === "idle" ? "START TEST" : "TEST AGAIN")
                    color: panel.deepBackgroundColor
                    font.family: "JetBrains Mono"
                    font.weight: Font.Black
                    font.letterSpacing: panel.s(0.45)
                    font.pixelSize: panel.s(10)
                }
            }

            MouseArea {
                id: startArea
                anchors.fill: parent
                enabled: !panel.running
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    panel.rootWindow.playSfx("switch.wav");
                    panel.rootWindow.runNativeSpeedtest();
                }
            }
        }
    }
}
