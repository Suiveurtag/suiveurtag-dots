import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: root
    focus: true

    property var notifModel
    property var liveNotifs
    property real layoutWidth: width
    property real layoutHeight: height

    Scaler {
        id: scaler
        currentWidth: Screen.width
        currentHeight: Screen.height
    }

    function s(value) {
        return scaler.s(value)
    }

    MatugenColors { id: theme }

    readonly property color base: theme.base
    readonly property color mantle: theme.mantle
    readonly property color crust: theme.crust
    readonly property color text: theme.text
    readonly property color subtext0: theme.subtext0
    readonly property color subtext1: theme.subtext1
    readonly property color surface0: theme.surface0
    readonly property color surface1: theme.surface1
    readonly property color surface2: theme.surface2
    readonly property color overlay0: theme.overlay0
    readonly property color mauve: theme.mauve
    readonly property color pink: theme.pink
    readonly property color sapphire: theme.sapphire
    readonly property color blue: theme.blue
    readonly property color teal: theme.teal
    readonly property color green: theme.green
    readonly property color peach: theme.peach
    readonly property color yellow: theme.yellow
    readonly property color red: theme.red

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string xdgDataHome: Quickshell.env("XDG_DATA_HOME")
    readonly property string dataHome: xdgDataHome !== "" ? xdgDataHome : homeDir + "/.local/share"
    readonly property string controllerPath: dataHome + "/quickshell-addons/tor-panel/tor_panelctl.py"

    property string torState: "unknown"
    property real bootstrapProgress: 0
    property real animatedProgress: bootstrapProgress
    property string statusDetail: "Lecture de l’état du réseau Tor…"
    property string socksAddress: "socket Unix privé"
    property bool busy: false
    property string activeAction: ""
    property string errorMessage: ""
    property var allApps: []
    property string searchQuery: ""
    property string activeFilter: "all"
    property int torAppCount: 0
    property real ambientPhase: 0
    property real introProgress: 0

    readonly property bool torRunning: torState === "running" || torState === "connected" || torState === "ready"
    readonly property bool torStarting: torState === "starting" || torState === "connecting"
    readonly property bool torEnabled: torRunning || torStarting
    readonly property color statusAccent: torRunning ? mauve
                                                      : (torStarting ? peach
                                                                     : (torState === "error" ? red : sapphire))
    readonly property color statusAccentSecondary: torRunning ? pink
                                                               : (torStarting ? yellow
                                                                              : (torState === "error" ? red : blue))
    readonly property string stateLabel: torRunning ? "CONNECTÉ"
                                                     : (torStarting ? "CONNEXION"
                                                                    : (torState === "error" ? "ERREUR" : "DÉCONNECTÉ"))

    Behavior on animatedProgress {
        NumberAnimation { duration: 720; easing.type: Easing.OutQuint }
    }

    NumberAnimation on ambientPhase {
        from: 0
        to: Math.PI * 2
        duration: 76000
        loops: Animation.Infinite
        running: root.visible
    }

    NumberAnimation on introProgress {
        id: introAnimation
        from: 0
        to: 1
        duration: 520
        easing.type: Easing.OutExpo
    }

    ListModel { id: appModel }

    function firstValue(object, names, fallbackValue) {
        if (!object) return fallbackValue
        for (let index = 0; index < names.length; index++) {
            const key = names[index]
            if (object[key] !== undefined && object[key] !== null)
                return object[key]
        }
        return fallbackValue
    }

    function normalizedState(value) {
        const state = String(value || "unknown").toLowerCase().replace(/_/g, "-")
        if (state === "active" || state === "online" || state === "bootstrapped") return "running"
        if (state === "inactive" || state === "offline" || state === "disabled") return "stopped"
        if (state === "activating" || state === "bootstrapping") return "starting"
        if (state === "failed" || state === "unavailable") return "error"
        return state
    }

    function compatibilityFor(app) {
        const raw = firstValue(app, ["support", "compatibility", "compatibility_state"], "")
        if (typeof raw === "string" && raw !== "") {
            const normalized = raw.toLowerCase()
            if (normalized === "unsupported" || normalized === "incompatible" || normalized === "false")
                return { state: "unsupported", label: "Non compatible" }
            if (normalized === "limited" || normalized === "partial" || normalized === "tcp-only" || normalized === "tcp")
                return { state: "partial", label: "Compatibilité limitée" }
            if (normalized === "strict")
                return { state: "compatible", label: "Isolation stricte" }
            if (normalized === "full" || normalized === "compatible" || normalized === "true")
                return { state: "compatible", label: "Compatible" }
            return { state: "compatible", label: raw }
        }
        const compatible = firstValue(app, ["compatible", "is_compatible"], true)
        return compatible ? { state: "compatible", label: "Compatible" }
                          : { state: "unsupported", label: "Non compatible" }
    }

    function isAppRouted(app) {
        const value = firstValue(app, ["tor", "routed", "tor_enabled", "use_tor"], false)
        if (typeof value === "string")
            return value === "tor" || value === "true" || value === "enabled"
        return Boolean(value)
    }

    function rebuildAppModel() {
        const query = searchQuery.trim().toLowerCase()
        appModel.clear()
        let routedCount = 0

        for (let index = 0; index < allApps.length; index++) {
            const app = allApps[index]
            const routed = isAppRouted(app)
            if (routed) routedCount++

            if (activeFilter === "tor" && !routed) continue
            if (activeFilter === "direct" && routed) continue

            const name = String(firstValue(app, ["name", "label"], "Application"))
            const appId = String(firstValue(app, ["id", "desktop_id", "desktopId"], name))
            const command = String(firstValue(app, ["exec", "command"], ""))
            if (query !== "" && (name + " " + appId + " " + command).toLowerCase().indexOf(query) === -1)
                continue

            const compatibility = compatibilityFor(app)
            appModel.append({
                appId: appId,
                appName: name,
                appIcon: String(firstValue(app, ["icon"], "")),
                appCommand: command,
                appReason: String(firstValue(app, ["reason"], "")),
                torRouted: routed,
                compatibilityState: compatibility.state,
                compatibilityLabel: compatibility.label
            })
        }

        torAppCount = routedCount
    }

    function applyStatusPayload(payload) {
        if (!payload) return
        if (payload.ok === false) {
            torState = "error"
            errorMessage = String(firstValue(payload, ["error", "message"], "Action Tor impossible"))
            return
        }
        const statusObject = payload.tor && typeof payload.tor === "object" ? payload.tor : payload
        let stateValue = firstValue(statusObject, ["state", "tor_state", "service_state"], "")
        if (stateValue === "" && typeof payload.status === "string" && payload.status !== "ok")
            stateValue = payload.status
        if (stateValue !== "") torState = normalizedState(stateValue)

        const progressValue = Number(firstValue(statusObject,
            ["bootstrap", "bootstrap_progress", "progress", "percent"], bootstrapProgress))
        if (!isNaN(progressValue)) {
            bootstrapProgress = Math.max(0, Math.min(100, progressValue))
            animatedProgress = bootstrapProgress
        }

        statusDetail = String(firstValue(statusObject,
            ["message", "detail", "summary"], torRunning ? "Circuit Tor prêt" : statusDetail))
        socksAddress = String(firstValue(statusObject,
            ["socks", "socks_address", "proxy"], socksAddress))
        const error = firstValue(payload, ["error", "error_message"], "")
        errorMessage = error ? String(error) : ""
    }

    function applyAppsPayload(payload) {
        if (payload && payload.ok === false) {
            errorMessage = String(firstValue(payload, ["error", "message"], "Catalogue d’applications indisponible"))
            return
        }
        const apps = Array.isArray(payload) ? payload
                                           : firstValue(payload, ["apps", "applications"], [])
        if (!Array.isArray(apps)) return
        allApps = apps
        rebuildAppModel()
    }

    function parseJson(textValue) {
        const raw = String(textValue || "").trim()
        if (raw === "") return null
        try {
            return JSON.parse(raw)
        } catch (error) {
            errorMessage = "Réponse invalide du contrôleur Tor"
            return null
        }
    }

    function refreshStatus() {
        if (!statusProcess.running)
            statusProcess.running = true
    }

    function refreshApps() {
        if (!appsProcess.running && !appActionProcess.running)
            appsProcess.running = true
    }

    function runTorAction(action) {
        if (busy || actionProcess.running) return
        busy = true
        activeAction = action
        errorMessage = ""
        actionProcess.command = action === "start" || action === "stop"
            ? ["python3", controllerPath, "network", action]
            : ["python3", controllerPath, action]
        actionProcess.running = true
    }

    function setAppRouted(appId, routed) {
        if (appActionProcess.running) return
        appActionProcess.command = ["python3", controllerPath, "set-route", appId, routed ? "on" : "off"]
        appActionProcess.running = true
    }

    Process {
        id: statusProcess
        command: ["python3", root.controllerPath, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const payload = root.parseJson(this.text)
                if (payload) root.applyStatusPayload(payload)
            }
        }
    }

    Process {
        id: appsProcess
        command: ["python3", root.controllerPath, "apps"]
        stdout: StdioCollector {
            onStreamFinished: {
                const payload = root.parseJson(this.text)
                if (payload) root.applyAppsPayload(payload)
            }
        }
    }

    Process {
        id: actionProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const payload = root.parseJson(this.text)
                if (payload) root.applyStatusPayload(payload)
            }
        }
        onExited: {
            root.busy = false
            root.activeAction = ""
            actionRefreshTimer.restart()
        }
    }

    Process {
        id: appActionProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const payload = root.parseJson(this.text)
                if (!payload) return
                if (payload.ok === false)
                    root.errorMessage = String(root.firstValue(payload, ["error", "message"], "Routage impossible"))
                else if (payload.apps || payload.applications)
                    root.applyAppsPayload(payload)
            }
        }
        onExited: appRefreshTimer.restart()
    }

    Timer {
        interval: 1300
        running: root.visible
        repeat: true
        onTriggered: root.refreshStatus()
    }

    Timer {
        id: actionRefreshTimer
        interval: 280
        onTriggered: root.refreshStatus()
    }

    Timer {
        id: appRefreshTimer
        interval: 180
        onTriggered: root.refreshApps()
    }

    Component.onCompleted: {
        refreshStatus()
        refreshApps()
        introAnimation.restart()
    }

    onVisibleChanged: {
        if (visible) {
            searchField.text = ""
            activeFilter = "all"
            introProgress = 0
            introAnimation.restart()
            refreshStatus()
            refreshApps()
            searchFocusTimer.restart()
        }
    }

    onSearchQueryChanged: rebuildAppModel()
    onActiveFilterChanged: rebuildAppModel()

    Keys.onEscapePressed: event => {
        Quickshell.execDetached([
            "bash",
            root.homeDir + "/.config/hypr/scripts/qs_manager.sh",
            "close"
        ])
        event.accepted = true
    }

    Timer {
        id: searchFocusTimer
        interval: 80
        onTriggered: searchField.forceActiveFocus()
    }

    Rectangle {
        id: shell
        anchors.fill: parent
        radius: root.s(24)
        color: root.base
        border.color: root.surface1
        border.width: 1
        clip: true

        Rectangle {
            width: parent.width * 0.66
            height: width
            radius: width / 2
            x: -width * 0.32 + Math.cos(root.ambientPhase) * root.s(46)
            y: -height * 0.46 + Math.sin(root.ambientPhase * 0.8) * root.s(34)
            color: root.mauve
            opacity: root.torRunning ? 0.105 : 0.048
            Behavior on color { ColorAnimation { duration: 800 } }
            Behavior on opacity { NumberAnimation { duration: 900 } }
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blur: 0.9; blurMax: 72 }
        }

        Rectangle {
            width: parent.width * 0.58
            height: width
            radius: width / 2
            x: parent.width - width * 0.64 + Math.sin(root.ambientPhase * 0.72) * root.s(42)
            y: parent.height - height * 0.56 + Math.cos(root.ambientPhase) * root.s(30)
            color: root.statusAccentSecondary
            opacity: root.torRunning ? 0.09 : 0.045
            Behavior on color { ColorAnimation { duration: 820 } }
            Behavior on opacity { NumberAnimation { duration: 900 } }
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blur: 0.9; blurMax: 72 }
        }

        Item {
            id: content
            anchors.fill: parent
            anchors.margins: root.s(22)
            opacity: root.introProgress
            transform: Translate { y: (1 - root.introProgress) * root.s(16) }

            RowLayout {
                id: header
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: root.s(58)
                spacing: root.s(13)

                Rectangle {
                    Layout.preferredWidth: root.s(48)
                    Layout.preferredHeight: root.s(48)
                    radius: root.s(16)
                    color: Qt.rgba(root.statusAccent.r, root.statusAccent.g, root.statusAccent.b, 0.14)
                    border.color: Qt.rgba(root.statusAccent.r, root.statusAccent.g, root.statusAccent.b, 0.48)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 620 } }
                    Behavior on border.color { ColorAnimation { duration: 620 } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰌾"
                        color: root.statusAccent
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: root.s(23)
                        Behavior on color { ColorAnimation { duration: 620 } }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "TOR NETWORK"
                        color: root.text
                        font.family: "JetBrains Mono"
                        font.pixelSize: root.s(19)
                        font.weight: Font.Black
                        font.letterSpacing: root.s(0.7)
                    }

                    Text {
                        text: "Circuit privé et routage par application"
                        color: root.subtext0
                        font.family: "JetBrains Mono"
                        font.pixelSize: root.s(10)
                    }
                }

                Rectangle {
                    Layout.preferredWidth: statusText.implicitWidth + root.s(28)
                    Layout.preferredHeight: root.s(31)
                    radius: height / 2
                    color: Qt.rgba(root.statusAccent.r, root.statusAccent.g, root.statusAccent.b, 0.12)
                    border.color: Qt.rgba(root.statusAccent.r, root.statusAccent.g, root.statusAccent.b, 0.44)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 650 } }
                    Behavior on border.color { ColorAnimation { duration: 650 } }

                    Row {
                        anchors.centerIn: parent
                        spacing: root.s(7)

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.s(7)
                            height: width
                            radius: width / 2
                            color: root.statusAccent

                            SequentialAnimation on opacity {
                                running: root.torStarting
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.28; duration: 620; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 620; easing.type: Easing.InOutSine }
                            }
                        }

                        Text {
                            id: statusText
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.stateLabel
                            color: root.statusAccent
                            font.family: "JetBrains Mono"
                            font.pixelSize: root.s(9)
                            font.weight: Font.Black
                            font.letterSpacing: root.s(0.45)
                            Behavior on color { ColorAnimation { duration: 650 } }
                        }
                    }
                }
            }

            RowLayout {
                anchors.top: header.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: noticeCard.top
                anchors.topMargin: root.s(14)
                anchors.bottomMargin: root.s(14)
                spacing: root.s(14)

                Rectangle {
                    id: statusCard
                    Layout.preferredWidth: root.s(315)
                    Layout.fillHeight: true
                    radius: root.s(20)
                    color: Qt.rgba(root.mantle.r, root.mantle.g, root.mantle.b, 0.91)
                    border.color: Qt.rgba(root.surface2.r, root.surface2.g, root.surface2.b, 0.62)
                    border.width: 1
                    clip: true

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: root.s(35)
                        width: root.s(238)
                        height: width
                        radius: width / 2
                        color: Qt.rgba(root.statusAccent.r, root.statusAccent.g, root.statusAccent.b, 0.055)
                        border.color: Qt.rgba(root.statusAccent.r, root.statusAccent.g, root.statusAccent.b, 0.13)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 750 } }
                        Behavior on border.color { ColorAnimation { duration: 750 } }

                        Repeater {
                            model: 3

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - root.s(34 + index * 42)
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.color: Qt.rgba(root.statusAccent.r, root.statusAccent.g, root.statusAccent.b,
                                                     0.28 - index * 0.055)
                                border.width: 1
                                rotation: index * 12 + root.ambientPhase * (index % 2 === 0 ? 5 : -4)
                            }
                        }

                        Canvas {
                            id: progressRing
                            anchors.centerIn: parent
                            width: root.s(190)
                            height: width
                            property real progressValue: root.animatedProgress
                            property color accentValue: root.statusAccent
                            onProgressValueChanged: requestPaint()
                            onAccentValueChanged: requestPaint()
                            Component.onCompleted: requestPaint()

                            onPaint: {
                                const context = getContext("2d")
                                context.reset()
                                const center = width / 2
                                const radius = width / 2 - root.s(7)
                                const start = -Math.PI / 2
                                const progress = Math.max(0, Math.min(1, progressValue / 100))
                                context.lineCap = "round"
                                context.lineWidth = root.s(6)
                                context.beginPath()
                                context.arc(center, center, radius, 0, Math.PI * 2)
                                context.strokeStyle = String(root.surface1)
                                context.globalAlpha = 0.72
                                context.stroke()
                                context.beginPath()
                                context.arc(center, center, radius, start, start + Math.PI * 2 * progress)
                                context.strokeStyle = String(accentValue)
                                context.globalAlpha = 1
                                context.stroke()
                            }
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: root.s(142)
                            height: width
                            radius: width / 2
                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0; color: Qt.lighter(root.statusAccent, 1.12) }
                                GradientStop { position: 1; color: root.statusAccentSecondary }
                            }
                            scale: root.torStarting ? 0.98 : 1
                            Behavior on scale { NumberAnimation { duration: 440; easing.type: Easing.OutBack } }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: root.s(3)
                                radius: width / 2
                                color: Qt.rgba(root.crust.r, root.crust.g, root.crust.b, 0.78)
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: root.s(1)

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "󰌾"
                                    color: root.statusAccent
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: root.s(34)
                                    Behavior on color { ColorAnimation { duration: 650 } }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Math.round(root.animatedProgress) + "%"
                                    color: root.text
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: root.s(18)
                                    font.weight: Font.Black
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "BOOTSTRAP"
                                    color: root.subtext0
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: root.s(7)
                                    font.weight: Font.Bold
                                    font.letterSpacing: root.s(0.8)
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: root.s(17)
                        anchors.rightMargin: root.s(17)
                        anchors.bottomMargin: root.s(17)
                        spacing: root.s(9)

                        Text {
                            Layout.fillWidth: true
                            text: root.errorMessage !== "" ? root.errorMessage : root.statusDetail
                            color: root.errorMessage !== "" ? root.red : root.subtext0
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            font.family: "JetBrains Mono"
                            font.pixelSize: root.s(9)
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(38)
                            radius: root.s(12)
                            color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.72)
                            border.color: Qt.rgba(root.surface2.r, root.surface2.g, root.surface2.b, 0.42)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: root.s(12)
                                anchors.rightMargin: root.s(12)

                                Text {
                                    text: "SOCKS5"
                                    color: root.subtext0
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: root.s(8)
                                    font.weight: Font.Bold
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: root.socksAddress
                                    color: root.text
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: root.s(9)
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(44)
                            spacing: root.s(8)

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: root.s(13)
                                color: masterAction.containsMouse
                                    ? Qt.lighter(root.statusAccent, 1.06)
                                    : root.statusAccent
                                opacity: root.busy ? 0.62 : 1
                                scale: masterAction.pressed ? 0.965 : 1
                                Behavior on color { ColorAnimation { duration: 220 } }
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: root.s(7)
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.busy ? "󰑐" : (root.torRunning ? "󰅖" : "󰐊")
                                        color: root.crust
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: root.s(14)
                                        RotationAnimation on rotation {
                                            from: 0; to: 360; duration: 900
                                            loops: Animation.Infinite
                                            running: root.busy
                                        }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.torEnabled ? "DÉCONNECTER" : "CONNECTER"
                                        color: root.crust
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: root.s(9)
                                        font.weight: Font.Black
                                    }
                                }

                                MouseArea {
                                    id: masterAction
                                    anchors.fill: parent
                                    enabled: !root.busy
                                    hoverEnabled: true
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.runTorAction(root.torEnabled ? "stop" : "start")
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: root.s(48)
                                Layout.fillHeight: true
                                radius: root.s(13)
                                color: identityAction.containsMouse ? root.surface2 : root.surface0
                                border.color: root.torRunning ? Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.45)
                                                                    : root.surface1
                                border.width: 1
                                opacity: root.torRunning && !root.busy ? 1 : 0.45
                                scale: identityAction.pressed ? 0.92 : 1
                                Behavior on color { ColorAnimation { duration: 180 } }
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰑐"
                                    color: root.text
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: root.s(17)
                                }

                                ToolTip.visible: identityAction.containsMouse
                                ToolTip.text: "Nouvelle identité"
                                ToolTip.delay: 350

                                MouseArea {
                                    id: identityAction
                                    anchors.fill: parent
                                    enabled: root.torRunning && !root.busy
                                    hoverEnabled: true
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.runTorAction("new-identity")
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: appsCard
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: root.s(20)
                    color: Qt.rgba(root.mantle.r, root.mantle.g, root.mantle.b, 0.91)
                    border.color: Qt.rgba(root.surface2.r, root.surface2.g, root.surface2.b, 0.62)
                    border.width: 1
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: root.s(15)
                        spacing: root.s(10)

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(40)
                            spacing: root.s(9)

                            Text {
                                text: "APPLICATIONS"
                                color: root.text
                                font.family: "JetBrains Mono"
                                font.pixelSize: root.s(13)
                                font.weight: Font.Black
                                font.letterSpacing: root.s(0.55)
                            }

                            Rectangle {
                                Layout.preferredWidth: countLabel.implicitWidth + root.s(16)
                                Layout.preferredHeight: root.s(23)
                                radius: height / 2
                                color: Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.12)
                                Text {
                                    id: countLabel
                                    anchors.centerIn: parent
                                    text: root.torAppCount + " via Tor"
                                    color: root.mauve
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: root.s(8)
                                    font.weight: Font.Bold
                                }
                            }

                            Item { Layout.fillWidth: true }

                            TextField {
                                id: searchField
                                Layout.preferredWidth: root.s(220)
                                Layout.preferredHeight: root.s(38)
                                color: root.text
                                placeholderText: "Rechercher…"
                                placeholderTextColor: root.subtext0
                                font.family: "JetBrains Mono"
                                font.pixelSize: root.s(10)
                                leftPadding: root.s(34)
                                rightPadding: root.s(12)
                                selectByMouse: true
                                onTextChanged: root.searchQuery = text

                                background: Rectangle {
                                    radius: root.s(12)
                                    color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.76)
                                    border.color: searchField.activeFocus ? root.mauve : root.surface1
                                    border.width: 1
                                    Behavior on border.color { ColorAnimation { duration: 180 } }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: root.s(12)
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "󰍉"
                                        color: searchField.activeFocus ? root.mauve : root.subtext0
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: root.s(13)
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: filters
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(36)
                            radius: root.s(12)
                            color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.68)
                            border.color: Qt.rgba(root.surface2.r, root.surface2.g, root.surface2.b, 0.36)
                            border.width: 1

                            property var entries: [
                                { key: "all", label: "Toutes" },
                                { key: "tor", label: "Tor" },
                                { key: "direct", label: "Direct" }
                            ]
                            property int activeIndex: root.activeFilter === "tor" ? 1 : (root.activeFilter === "direct" ? 2 : 0)
                            property real segmentWidth: (width - root.s(8)) / 3

                            Rectangle {
                                x: root.s(4) + filters.activeIndex * filters.segmentWidth
                                y: root.s(4)
                                width: filters.segmentWidth
                                height: parent.height - root.s(8)
                                radius: root.s(9)
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: root.activeFilter === "direct" ? root.sapphire : root.mauve }
                                    GradientStop { position: 1; color: root.activeFilter === "direct" ? root.blue : root.pink }
                                }
                                Behavior on x {
                                    NumberAnimation { duration: 430; easing.type: Easing.OutBack; easing.overshoot: 1.05 }
                                }
                            }

                            Row {
                                anchors.fill: parent
                                anchors.margins: root.s(4)

                                Repeater {
                                    model: filters.entries

                                    Item {
                                        required property var modelData
                                        width: filters.segmentWidth
                                        height: parent.height
                                        scale: filterMouse.pressed ? 0.92 : 1
                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: parent.modelData.label
                                            color: root.activeFilter === parent.modelData.key ? root.crust : root.subtext0
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: root.s(9)
                                            font.weight: Font.Black
                                            Behavior on color { ColorAnimation { duration: 240 } }
                                        }

                                        MouseArea {
                                            id: filterMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.activeFilter = parent.modelData.key
                                        }
                                    }
                                }
                            }
                        }

                        ListView {
                            id: appsList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: appModel
                            spacing: root.s(6)
                            boundsBehavior: Flickable.StopAtBounds

                            add: Transition {
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 300; easing.type: Easing.OutExpo }
                                    NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 340; easing.type: Easing.OutBack }
                                }
                            }
                            remove: Transition {
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; to: 0; duration: 180 }
                                    NumberAnimation { property: "scale"; to: 0.96; duration: 210 }
                                }
                            }
                            displaced: Transition {
                                NumberAnimation { properties: "x,y"; duration: 310; easing.type: Easing.OutExpo }
                            }

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle {
                                    implicitWidth: root.s(4)
                                    radius: width / 2
                                    color: root.surface2
                                    opacity: 0.7
                                }
                            }

                            delegate: Rectangle {
                                id: appRow
                                required property int index
                                required property string appId
                                required property string appName
                                required property string appIcon
                                required property string appCommand
                                required property string appReason
                                required property bool torRouted
                                required property string compatibilityState
                                required property string compatibilityLabel

                                width: ListView.view.width - root.s(6)
                                height: root.s(61)
                                radius: root.s(14)
                                color: rowMouse.containsMouse
                                    ? Qt.rgba(root.surface1.r, root.surface1.g, root.surface1.b, 0.76)
                                    : Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.62)
                                border.color: torRouted
                                    ? Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.38)
                                    : Qt.rgba(root.surface2.r, root.surface2.g, root.surface2.b, 0.28)
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 190 } }
                                Behavior on border.color { ColorAnimation { duration: 300 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: root.s(9)
                                    spacing: root.s(10)

                                    Rectangle {
                                        Layout.preferredWidth: root.s(42)
                                        Layout.preferredHeight: root.s(42)
                                        radius: root.s(12)
                                        color: torRouted
                                            ? Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.16)
                                            : Qt.rgba(root.sapphire.r, root.sapphire.g, root.sapphire.b, 0.11)
                                        Behavior on color { ColorAnimation { duration: 320 } }

                                        Image {
                                            id: appImage
                                            anchors.centerIn: parent
                                            width: root.s(25)
                                            height: width
                                            source: appRow.appIcon === "" ? ""
                                                : (appRow.appIcon.startsWith("/") ? "file://" + appRow.appIcon
                                                                                  : "image://icon/" + appRow.appIcon)
                                            sourceSize: Qt.size(64, 64)
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                            smooth: true
                                            mipmap: true
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            visible: appRow.appIcon === "" || appImage.status === Image.Error
                                            text: "󰣆"
                                            color: appRow.torRouted ? root.mauve : root.sapphire
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: root.s(18)
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: root.s(2)

                                        Text {
                                            Layout.fillWidth: true
                                            text: appRow.appName
                                            color: root.text
                                            elide: Text.ElideRight
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: root.s(11)
                                            font.weight: Font.DemiBold
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: appRow.appReason !== ""
                                                ? appRow.appReason
                                                : (appRow.appCommand !== "" ? appRow.appCommand : appRow.appId)
                                            color: root.subtext0
                                            opacity: 0.72
                                            elide: Text.ElideRight
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: root.s(7)
                                        }
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: compatibilityText.implicitWidth + root.s(14)
                                        Layout.preferredHeight: root.s(22)
                                        radius: height / 2
                                        color: appRow.compatibilityState === "unsupported"
                                            ? Qt.rgba(root.red.r, root.red.g, root.red.b, 0.12)
                                            : (appRow.compatibilityState === "partial"
                                                ? Qt.rgba(root.peach.r, root.peach.g, root.peach.b, 0.12)
                                                : Qt.rgba(root.green.r, root.green.g, root.green.b, 0.11))

                                        Text {
                                            id: compatibilityText
                                            anchors.centerIn: parent
                                            text: appRow.compatibilityLabel
                                            color: appRow.compatibilityState === "unsupported" ? root.red
                                                : (appRow.compatibilityState === "partial" ? root.peach : root.green)
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: root.s(7)
                                            font.weight: Font.Bold
                                        }
                                    }

                                    Rectangle {
                                        id: routeSwitch
                                        Layout.preferredWidth: root.s(52)
                                        Layout.preferredHeight: root.s(29)
                                        radius: height / 2
                                        color: appRow.torRouted
                                            ? Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.66)
                                            : Qt.rgba(root.surface2.r, root.surface2.g, root.surface2.b, 0.65)
                                        border.color: appRow.torRouted ? root.mauve : root.overlay0
                                        border.width: 1
                                        opacity: appRow.compatibilityState === "unsupported" ? 0.42 : 1
                                        Behavior on color { ColorAnimation { duration: 300 } }
                                        Behavior on border.color { ColorAnimation { duration: 300 } }

                                        Rectangle {
                                            x: appRow.torRouted ? parent.width - width - root.s(4) : root.s(4)
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: root.s(21)
                                            height: width
                                            radius: width / 2
                                            color: appRow.torRouted ? root.crust : root.text
                                            Behavior on x {
                                                NumberAnimation { duration: 390; easing.type: Easing.OutBack; easing.overshoot: 1.08 }
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                text: appRow.torRouted ? "󰌾" : ""
                                                color: root.mauve
                                                font.family: "Iosevka Nerd Font"
                                                font.pixelSize: root.s(10)
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: rowMouse
                                    anchors.fill: parent
                                    enabled: appRow.compatibilityState !== "unsupported" && !appActionProcess.running
                                    hoverEnabled: true
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.setAppRouted(appRow.appId, !appRow.torRouted)
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: appModel.count === 0
                                text: root.searchQuery !== "" ? "Aucune application trouvée" : "Aucune application dans ce filtre"
                                color: root.subtext0
                                font.family: "JetBrains Mono"
                                font.pixelSize: root.s(11)
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: noticeCard
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: root.s(48)
                radius: root.s(14)
                color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.72)
                border.color: Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.26)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: root.s(14)
                    anchors.rightMargin: root.s(14)
                    spacing: root.s(10)

                    Rectangle {
                        Layout.preferredWidth: root.s(28)
                        Layout.preferredHeight: root.s(28)
                        radius: width / 2
                        color: Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.13)

                        Text {
                            anchors.centerIn: parent
                            text: "󰋽"
                            color: root.mauve
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: root.s(14)
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Les changements s’appliquent au prochain lancement de l’application. Seul le trafic TCP est routé via Tor."
                        color: root.subtext0
                        elide: Text.ElideRight
                        font.family: "JetBrains Mono"
                        font.pixelSize: root.s(9)
                    }
                }
            }
        }
    }
}
