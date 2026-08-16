import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io

Item {
    id: root

    required property var rootWindow

    property string mode: "loading"
    property string pendingMode: ""
    property string connectionName: ""
    property string errorMessage: ""
    property bool busy: false

    readonly property string displayedMode: busy && pendingMode !== "" ? pendingMode : mode
    readonly property bool isMullvad: displayedMode === "mullvad"
    readonly property color homeAccent: rootWindow.sapphire
    readonly property color homeSecondary: rootWindow.blue
    readonly property color mullvadAccent: rootWindow.mauve
    readonly property color mullvadSecondary: rootWindow.pink
    readonly property color currentAccent: isMullvad ? mullvadAccent : homeAccent
    readonly property color currentSecondary: isMullvad ? mullvadSecondary : homeSecondary

    function s(value) {
        return rootWindow.s(value);
    }

    function applyPayload(rawText) {
        const raw = String(rawText || "").trim();
        if (raw === "") return;
        try {
            const payload = JSON.parse(raw);
            connectionName = payload.connection || "";
            if (payload.status === "ok") {
                mode = payload.mode || "custom";
                errorMessage = "";
            } else {
                mode = "unavailable";
                errorMessage = payload.message || "DNS unavailable";
            }
        } catch (error) {
            mode = "unavailable";
            errorMessage = "Invalid DNS response";
        }
    }

    function refreshStatus() {
        if (!statusProcess.running && !switchProcess.running)
            statusProcess.running = true;
    }

    function selectMode(nextMode) {
        if (busy || nextMode === mode) return;
        busy = true;
        pendingMode = nextMode;
        errorMessage = "";
        switchProcess.command = [
            "bash",
            rootWindow.scriptsDir + "/dns_mode_toggle.sh",
            "set",
            nextMode
        ];
        switchProcess.running = true;
    }

    width: s(224)
    height: s(48)
    visible: rootWindow.activeMode === "wifi"
        && rootWindow.wifiPresent
        && rootWindow.currentPower

    onVisibleChanged: if (visible) refreshStatus()
    Component.onCompleted: refreshStatus()

    Process {
        id: statusProcess
        command: ["bash", root.rootWindow.scriptsDir + "/dns_mode_toggle.sh", "status"]
        stdout: StdioCollector {
            onStreamFinished: root.applyPayload(this.text)
        }
    }

    Process {
        id: switchProcess
        stdout: StdioCollector {
            onStreamFinished: root.applyPayload(this.text)
        }
        onExited: {
            root.busy = false;
            root.pendingMode = "";
            statusRefreshDelay.restart();
        }
    }

    Timer {
        interval: 4000
        running: root.visible
        repeat: true
        onTriggered: root.refreshStatus()
    }

    Timer {
        id: statusRefreshDelay
        interval: 220
        onTriggered: root.refreshStatus()
    }

    MultiEffect {
        source: toggleFrame
        anchors.fill: toggleFrame
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: 0.38
        shadowBlur: 1.0
        shadowVerticalOffset: root.s(4)
    }

    Rectangle {
        id: toggleFrame
        anchors.fill: parent
        radius: root.s(16)
        color: Qt.rgba(root.rootWindow.surface0.r, root.rootWindow.surface0.g, root.rootWindow.surface0.b, 0.94)
        border.color: root.errorMessage !== ""
            ? root.rootWindow.red
            : Qt.rgba(root.currentAccent.r, root.currentAccent.g, root.currentAccent.b, 0.56)
        border.width: root.s(1.5)
        clip: true

        Behavior on border.color {
            ColorAnimation { duration: 380; easing.type: Easing.InOutCubic }
        }

        Rectangle {
            id: activeSegment
            x: root.s(4) + (root.isMullvad ? width : 0)
            y: root.s(4)
            width: (parent.width - root.s(8)) / 2
            height: parent.height - root.s(8)
            radius: root.s(13)

            Behavior on x {
                NumberAnimation {
                    duration: 480
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.08
                }
            }

            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.lighter(root.currentAccent, 1.12) }
                GradientStop { position: 1; color: root.currentSecondary }
            }

            Behavior on color {
                ColorAnimation { duration: 420 }
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.22)
                border.width: 1
            }
        }

        Row {
            anchors.fill: parent
            anchors.margins: root.s(4)

            Repeater {
                model: [
                    { mode: "home", icon: "󰖟", label: "Home" },
                    { mode: "mullvad", icon: "󰌾", label: "Mullvad" }
                ]

                Item {
                    required property var modelData
                    width: (toggleFrame.width - root.s(8)) / 2
                    height: toggleFrame.height - root.s(8)

                    readonly property bool selected: root.displayedMode === modelData.mode

                    Row {
                        anchors.centerIn: parent
                        spacing: root.s(6)

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.icon
                            color: parent.parent.selected ? root.rootWindow.crust : root.rootWindow.subtext0
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: root.s(15)
                            Behavior on color { ColorAnimation { duration: 300 } }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: parent.parent.selected ? root.rootWindow.crust : root.rootWindow.subtext0
                            font.family: "JetBrains Mono"
                            font.weight: Font.Black
                            font.pixelSize: root.s(11)
                            Behavior on color { ColorAnimation { duration: 300 } }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.busy
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            root.rootWindow.playSfx("switch.wav");
                            root.selectMode(parent.modelData.mode);
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: root.s(18)
            height: width
            radius: width / 2
            color: root.rootWindow.surface1
            border.color: root.currentAccent
            border.width: 1
            visible: root.busy

            Text {
                anchors.centerIn: parent
                text: "󰑐"
                color: root.rootWindow.text
                font.family: "Iosevka Nerd Font"
                font.pixelSize: root.s(11)

                RotationAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 850
                    loops: Animation.Infinite
                    running: root.busy
                }
            }
        }
    }
}
