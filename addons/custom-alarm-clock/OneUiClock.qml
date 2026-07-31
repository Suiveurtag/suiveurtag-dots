import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "." as AlarmSystem

Item {
    id: root

    property var controller: null
    property var scaleFunc: function(value) { return value; }
    property color baseColor: "#1e1e2e"
    property color mantleColor: "#181825"
    property color surface0Color: "#313244"
    property color surface1Color: "#45475a"
    property color surface2Color: "#585b70"
    property color textColor: "#cdd6f4"
    property color subtextColor: "#a6adc8"
    property color accentColor: "#cba6f7"
    property color blueColor: "#89b4fa"
    property color sapphireColor: "#74c7ec"
    property color pinkColor: "#f5c2e7"
    property color greenColor: "#a6e3a1"
    property color redColor: "#f38ba8"
    property string iconFont: "Font Awesome 6 Free Solid"
    property bool animateBackground: true
    readonly property bool verticalMode: height > width * 1.18
    readonly property real interfaceScale: verticalMode ? 1.16 : 1.06

    readonly property int activeMode: controller ? controller.alarmActiveMode : 0
    readonly property bool timerRunning: controller ? controller.clockTimerRunning : false
    readonly property bool timerIdle: controller ? controller.clockTimerIdle : true
    readonly property real timerRemainingMs: controller ? controller.clockTimerRemainingMs : 0
    readonly property real timerPresetMs: controller ? controller.clockTimerPresetMs : 0
    readonly property bool stopwatchRunning: controller ? controller.clockStopwatchRunning : false
    readonly property real stopwatchMs: controller ? controller.clockStopwatchMs : 0
    readonly property var lapData: controller ? controller.clockLapData : []
    readonly property bool pomodoroRunning: controller ? controller.clockPomodoroRunning : false
    readonly property real pomodoroRemainingMs: controller ? controller.clockPomodoroRemainingMs : 0
    readonly property int pomodoroState: controller ? controller.clockPomodoroState : 0
    readonly property int pomodoroSessions: controller ? controller.clockPomodoroSessions : 0
    readonly property int pomodoroTargetSessions: controller ? controller.clockPomodoroTargetSessions : 4
    readonly property int pomodoroWorkLimit: controller ? controller.clockPomodoroWorkLimit : 25
    readonly property int pomodoroShortLimit: controller ? controller.clockPomodoroShortLimit : 5
    readonly property int pomodoroLongLimit: controller ? controller.clockPomodoroLongLimit : 15
    readonly property bool alarmEditorOpen: alarmPage.editorOpen

    property int timerSegment: 1
    property bool pomodoroSettingsOpen: false
    property int previousMode: 0
    property int transitionDirection: 1

    function s(value) {
        const scaled = typeof scaleFunc === "function" ? scaleFunc(value) : value;
        return scaled * interfaceScale;
    }

    function alpha(color, amount) {
        return Qt.rgba(color.r, color.g, color.b, amount);
    }

    function formatTime(milliseconds, includeMilliseconds) {
        if (controller && typeof controller.formatTime === "function")
            return controller.formatTime(milliseconds, includeMilliseconds);
        return "00:00";
    }

    function pomodoroPhaseLabel() {
        if (pomodoroState === 0)
            return "Focus";
        if (pomodoroState === 1)
            return "Short break";
        return "Long break";
    }

    function pomodoroLimitMs() {
        if (pomodoroState === 0)
            return pomodoroWorkLimit * 60000;
        if (pomodoroState === 1)
            return pomodoroShortLimit * 60000;
        return pomodoroLongLimit * 60000;
    }

    function openAlarmEditor() {
        alarmPage.openNewAlarm();
    }

    function commitAlarmEditor() {
        alarmPage.commitEditor();
    }

    function modeIsVisible(mode, opacityValue) {
        return activeMode === mode || opacityValue > 0.001;
    }

    onActiveModeChanged: {
        transitionDirection = activeMode >= previousMode ? 1 : -1;
        previousMode = activeMode;
        if (activeMode !== 2)
            pomodoroSettingsOpen = false;
    }

    component RoundButton: Rectangle {
        id: button

        property string label: ""
        property string icon: ""
        property bool accented: false
        property bool destructive: false
        property bool enabledButton: true
        property real buttonSize: root.s(50)
        signal clicked()

        width: buttonSize
        height: buttonSize
        radius: width / 2
        scale: buttonMouse.pressed ? 0.90 : 1.0
        opacity: enabledButton ? 1.0 : 0.38
        color: {
            if (destructive)
                return root.alpha(root.redColor, buttonMouse.containsMouse ? 0.38 : 0.25);
            if (accented)
                return root.alpha(root.accentColor, buttonMouse.containsMouse ? 0.55 : 0.38);
            return buttonMouse.containsMouse
                ? root.alpha(root.surface2Color, 0.92)
                : root.alpha(root.surface1Color, 0.78);
        }
        border.width: 1
        border.color: destructive
            ? root.alpha(root.redColor, 0.56)
            : (accented ? root.alpha(root.accentColor, 0.66) : root.alpha(root.textColor, 0.13))

        Behavior on scale {
            NumberAnimation {
                duration: 170
                easing.type: Easing.OutBack
            }
        }

        Behavior on color {
            ColorAnimation { duration: 180 }
        }

        Column {
            anchors.centerIn: parent
            spacing: root.s(1)

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: text !== ""
                text: button.icon
                color: button.destructive
                    ? root.redColor
                    : (button.accented ? root.accentColor : root.textColor)
                font.family: root.iconFont
                font.pixelSize: root.s(button.label === "" ? 14 : 11)
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: text !== ""
                text: button.label
                color: button.destructive
                    ? root.redColor
                    : (button.accented ? root.accentColor : root.textColor)
                font.family: "Noto Sans"
                font.pixelSize: root.s(8)
                font.weight: Font.DemiBold
            }
        }

        MouseArea {
            id: buttonMouse

            anchors.fill: parent
            enabled: button.enabledButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    component WheelColumn: AnimatedNumberWheel {
        scaleFunc: root.s
        textColor: root.textColor
        subtextColor: root.subtextColor
        accentColor: root.accentColor
    }

    component SettingRow: Item {
        id: settingRow

        property string label: ""
        property string target: ""
        property int value: 0
        property int step: 1
        property int minimum: 1
        property int maximum: 60

        width: parent ? parent.width : root.s(170)
        height: root.s(28)

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: settingRow.label
            color: root.subtextColor
            font.family: "Noto Sans"
            font.pixelSize: root.s(9)
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.s(5)

            Rectangle {
                width: root.s(24)
                height: width
                radius: width / 2
                color: minusMouse.containsMouse
                    ? root.alpha(root.surface2Color, 0.95)
                    : root.alpha(root.surface1Color, 0.78)

                Text {
                    anchors.centerIn: parent
                    text: "−"
                    color: root.textColor
                    font.family: "Noto Sans"
                    font.pixelSize: root.s(13)
                }

                MouseArea {
                    id: minusMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.controller)
                            root.controller.clockAdjustPomodoro(
                                settingRow.target,
                                -settingRow.step,
                                settingRow.minimum,
                                settingRow.maximum
                            );
                    }
                }
            }

            Text {
                width: root.s(28)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: settingRow.value
                color: root.textColor
                font.family: "Noto Sans"
                font.pixelSize: root.s(10)
                font.weight: Font.Bold
            }

            Rectangle {
                width: root.s(24)
                height: width
                radius: width / 2
                color: plusMouse.containsMouse
                    ? root.alpha(root.surface2Color, 0.95)
                    : root.alpha(root.surface1Color, 0.78)

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: root.textColor
                    font.family: "Noto Sans"
                    font.pixelSize: root.s(13)
                }

                MouseArea {
                    id: plusMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.controller)
                            root.controller.clockAdjustPomodoro(
                                settingRow.target,
                                settingRow.step,
                                settingRow.minimum,
                                settingRow.maximum
                            );
                    }
                }
            }
        }
    }

    LiquidBackground {
        anchors.fill: parent
        activeMode: root.activeMode
        animate: root.animateBackground
        scaleFunc: root.scaleFunc
        baseColor: root.mantleColor
        primaryColor: root.accentColor
        secondaryColor: root.blueColor
        tertiaryColor: root.pinkColor
        breakColor: root.greenColor
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    Item {
        id: interfaceStage

        anchors.centerIn: parent
        width: parent.width
        height: root.verticalMode
            ? Math.min(parent.height - root.s(28), root.s(520))
            : parent.height

    Item {
        id: header

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.s(10)
        anchors.leftMargin: root.s(16)
        anchors.rightMargin: root.s(12)
        height: root.s(34)

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: ["Timer", "Stopwatch", "Pomodoro", "Alarm"][root.activeMode]
            color: root.textColor
            font.family: "Noto Sans"
            font.pixelSize: root.s(16)
            font.weight: Font.Bold

            Behavior on opacity {
                NumberAnimation { duration: 220 }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.s(5)

            Rectangle {
                visible: root.activeMode === 3
                width: root.s(29)
                height: width
                radius: width / 2
                color: alarmAddMouse.containsMouse
                    ? root.alpha(root.surface2Color, 0.82)
                    : root.alpha(root.surface1Color, 0.45)
                scale: alarmAddMouse.pressed ? 0.86 : 1

                Behavior on scale {
                    NumberAnimation {
                        duration: 170
                        easing.type: Easing.OutBack
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: root.textColor
                    font.family: "Noto Sans"
                    font.pixelSize: root.s(18)
                    font.weight: Font.Light
                }

                MouseArea {
                    id: alarmAddMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openAlarmEditor()
                }
            }

            Rectangle {
                width: root.s(29)
                height: width
                radius: width / 2
                color: soundMouse.containsMouse
                    ? root.alpha(root.surface2Color, 0.82)
                    : root.alpha(root.surface1Color, 0.45)
                border.width: AlarmSystem.AlarmManager.soundFor(
                    root.controller ? root.controller.activeModeKey() : "timer"
                ).source !== "" ? 1 : 0
                border.color: root.alpha(root.accentColor, 0.7)
                scale: soundMouse.pressed ? 0.86 : 1

                Behavior on scale {
                    NumberAnimation {
                        duration: 170
                        easing.type: Easing.OutBack
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: AlarmSystem.AlarmManager.isRinging ? "\uF04D" : "\uF001"
                    color: AlarmSystem.AlarmManager.isRinging ? root.redColor : root.textColor
                    font.family: root.iconFont
                    font.pixelSize: root.s(11)
                }

                MouseArea {
                    id: soundMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (AlarmSystem.AlarmManager.isRinging)
                            AlarmSystem.AlarmManager.stopPlayback(true);
                        else if (root.controller)
                            root.controller.openAlarmSoundSettings();
                    }
                }
            }
        }
    }

    Item {
        id: content

        anchors.top: header.bottom
        anchors.bottom: navigation.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.s(1)
        anchors.bottomMargin: root.s(5)
        anchors.leftMargin: root.s(12)
        anchors.rightMargin: root.s(12)
        clip: true

        Item {
            id: timerPage

            anchors.fill: parent
            enabled: root.activeMode === 0
            opacity: root.activeMode === 0 ? 1 : 0
            scale: root.activeMode === 0 ? 1 : 0.965
            x: root.activeMode === 0 ? 0 : -root.transitionDirection * root.s(12)
            visible: root.modeIsVisible(0, opacity)

            Behavior on opacity {
                NumberAnimation {
                    duration: 330
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: 390
                    easing.type: Easing.OutBack
                }
            }
            Behavior on x {
                NumberAnimation {
                    duration: 390
                    easing.type: Easing.OutCubic
                }
            }

            Item {
                id: timerPickerLayer

                anchors.fill: parent
                enabled: root.timerIdle
                opacity: root.timerIdle ? 1 : 0
                scale: root.timerIdle ? 1 : 0.90
                y: root.timerIdle ? 0 : root.s(12)
                visible: root.timerIdle || opacity > 0.001

                Behavior on opacity {
                    NumberAnimation {
                        duration: 310
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 420
                        easing.type: Easing.OutBack
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: 360
                        easing.type: Easing.OutCubic
                    }
                }

                Row {
                    anchors.top: parent.top
                    anchors.topMargin: root.verticalMode ? root.s(42) : root.s(2)
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: root.s(4)

                    WheelColumn {
                        label: "Hours"
                        value: Math.floor(root.timerPresetMs / 3600000)
                        maximum: 99
                        selected: root.timerSegment === 0
                        onSelectedRequested: root.timerSegment = 0
                        onDeltaRequested: delta => {
                            if (root.controller)
                                root.controller.clockAdjustTimerSegment(0, delta);
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: root.s(9)
                        text: ":"
                        color: root.textColor
                        font.family: "Noto Sans"
                        font.pixelSize: root.s(26)
                        font.weight: Font.Bold
                    }

                    WheelColumn {
                        label: "Minutes"
                        value: Math.floor((root.timerPresetMs % 3600000) / 60000)
                        selected: root.timerSegment === 1
                        onSelectedRequested: root.timerSegment = 1
                        onDeltaRequested: delta => {
                            if (root.controller)
                                root.controller.clockAdjustTimerSegment(1, delta);
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: root.s(9)
                        text: ":"
                        color: root.textColor
                        font.family: "Noto Sans"
                        font.pixelSize: root.s(26)
                        font.weight: Font.Bold
                    }

                    WheelColumn {
                        label: "Seconds"
                        value: Math.floor((root.timerPresetMs % 60000) / 1000)
                        selected: root.timerSegment === 2
                        onSelectedRequested: root.timerSegment = 2
                        onDeltaRequested: delta => {
                            if (root.controller)
                                root.controller.clockAdjustTimerSegment(2, delta);
                        }
                    }
                }

                Row {
                    anchors.top: parent.top
                    anchors.topMargin: root.verticalMode ? root.s(178) : root.s(121)
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: root.s(7)

                    Repeater {
                        model: [
                            { label: "10 min", milliseconds: 10 * 60000 },
                            { label: "15 min", milliseconds: 15 * 60000 },
                            { label: "30 min", milliseconds: 30 * 60000 }
                        ]

                        Rectangle {
                            id: presetChip
                            required property var modelData

                            width: root.s(62)
                            height: root.s(25)
                            radius: height / 2
                            color: presetMouse.containsMouse
                                ? root.alpha(root.surface2Color, 0.88)
                                : root.alpha(root.surface1Color, 0.63)
                            border.width: 1
                            border.color: root.alpha(root.textColor, 0.10)
                            scale: presetMouse.pressed ? 0.92 : 1

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.OutBack
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: presetChip.modelData.label
                                color: root.textColor
                                font.family: "Noto Sans"
                                font.pixelSize: root.s(8)
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                id: presetMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.controller)
                                        root.controller.clockSetTimerPreset(presetChip.modelData.milliseconds);
                                }
                            }
                        }
                    }
                }

                RoundButton {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.s(3)
                    anchors.horizontalCenter: parent.horizontalCenter
                    buttonSize: root.s(53)
                    label: "Start"
                    accented: true
                    enabledButton: root.timerPresetMs > 0
                    onClicked: {
                        if (root.controller)
                            root.controller.clockToggle();
                    }
                }
            }

            Item {
                id: timerRunningLayer

                anchors.fill: parent
                enabled: !root.timerIdle
                opacity: root.timerIdle ? 0 : 1
                scale: root.timerIdle ? 0.84 : 1
                y: root.timerIdle ? -root.s(12) : 0
                visible: !root.timerIdle || opacity > 0.001

                Behavior on opacity {
                    NumberAnimation {
                        duration: 320
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 440
                        easing.type: Easing.OutBack
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: 380
                        easing.type: Easing.OutCubic
                    }
                }

                ClockDial {
                    anchors.top: parent.top
                    anchors.topMargin: root.verticalMode ? root.s(34) : root.s(2)
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.s(root.verticalMode ? 176 : 151)
                    height: width
                    scaleFunc: root.s
                    primaryColor: root.accentColor
                    secondaryColor: root.blueColor
                    surfaceColor: root.surface0Color
                    textColor: root.textColor
                    subtextColor: root.subtextColor
                    progress: root.timerPresetMs > 0
                        ? root.timerRemainingMs / root.timerPresetMs
                        : 0
                    handVisible: true
                    handAngle: root.timerPresetMs > 0
                        ? root.timerRemainingMs / root.timerPresetMs * 360
                        : 0
                    mainText: root.formatTime(root.timerRemainingMs, false)
                    eyebrowText: root.formatTime(root.timerPresetMs, false) + " total"
                    detailText: root.timerRunning ? "Counting down" : "Paused"
                }

                Row {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.s(3)
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: root.s(80)

                    RoundButton {
                        buttonSize: root.s(50)
                        label: "Cancel"
                        onClicked: {
                            if (root.controller)
                                root.controller.clockResetTimer();
                        }
                    }

                    RoundButton {
                        buttonSize: root.s(50)
                        label: root.timerRunning ? "Pause" : "Resume"
                        accented: !root.timerRunning
                        destructive: root.timerRunning
                        onClicked: {
                            if (root.controller)
                                root.controller.clockToggle();
                        }
                    }
                }
            }
        }

        Item {
            id: stopwatchPage

            anchors.fill: parent
            enabled: root.activeMode === 1
            opacity: root.activeMode === 1 ? 1 : 0
            scale: root.activeMode === 1 ? 1 : 0.965
            x: root.activeMode === 1 ? 0 : -root.transitionDirection * root.s(12)
            visible: root.modeIsVisible(1, opacity)

            Behavior on opacity {
                NumberAnimation {
                    duration: 330
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: 390
                    easing.type: Easing.OutBack
                }
            }
            Behavior on x {
                NumberAnimation {
                    duration: 390
                    easing.type: Easing.OutCubic
                }
            }

            ClockDial {
                id: stopwatchDial

                x: root.verticalMode ? (parent.width - width) / 2 : root.s(12)
                y: root.verticalMode ? root.s(18) : root.s(5)
                width: root.s(root.verticalMode ? 174 : 147)
                height: width
                scaleFunc: root.s
                primaryColor: root.blueColor
                secondaryColor: root.accentColor
                surfaceColor: root.surface0Color
                textColor: root.textColor
                subtextColor: root.subtextColor
                progress: (root.stopwatchMs % 60000) / 60000
                handAngle: (root.stopwatchMs % 60000) / 60000 * 360
                handVisible: true
                mainText: root.formatTime(root.stopwatchMs, true)
                detailText: root.stopwatchRunning ? "Running" : (root.stopwatchMs > 0 ? "Paused" : "Ready")
            }

            Item {
                x: root.verticalMode ? root.s(24) : root.s(184)
                y: root.verticalMode
                    ? stopwatchDial.y + stopwatchDial.height + root.s(12)
                    : root.s(8)
                width: parent.width - x - (root.verticalMode ? root.s(24) : 0)
                height: parent.height - y - root.s(60)

                Rectangle {
                    id: stopwatchAlarmChip

                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: root.s(29)
                    radius: height / 2
                    color: AlarmSystem.AlarmManager.stopwatchEnabled
                        ? root.alpha(root.accentColor, 0.18)
                        : root.alpha(root.surface1Color, 0.58)
                    border.width: 1
                    border.color: AlarmSystem.AlarmManager.stopwatchEnabled
                        ? root.alpha(root.accentColor, 0.55)
                        : root.alpha(root.textColor, 0.08)

                    Text {
                        anchors.centerIn: parent
                        text: AlarmSystem.AlarmManager.stopwatchEnabled
                            ? "Alarm  " + root.formatTime(
                                AlarmSystem.AlarmManager.stopwatchTargetMs,
                                false
                            )
                            : "Set a target alarm"
                        color: AlarmSystem.AlarmManager.stopwatchEnabled
                            ? root.accentColor
                            : root.subtextColor
                        font.family: "Noto Sans"
                        font.pixelSize: root.s(8)
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.controller)
                                root.controller.openAlarmSoundSettings();
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.lapData.length === 0
                    text: "Your laps will appear here"
                    color: root.alpha(root.subtextColor, 0.62)
                    font.family: "Noto Sans"
                    font.pixelSize: root.s(9)
                }

                ListView {
                    id: compactLapList

                    anchors.top: stopwatchAlarmChip.bottom
                    anchors.topMargin: root.s(6)
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    visible: root.lapData.length > 0
                    model: root.lapData.length
                    spacing: root.s(3)
                    clip: true

                    delegate: Rectangle {
                        id: compactLapDelegate
                        required property int index

                        property int sourceIndex: root.lapData.length - 1 - index
                        property var lapItem: root.lapData[sourceIndex]

                        width: compactLapList.width
                        height: root.s(27)
                        radius: root.s(9)
                        color: root.alpha(root.surface1Color, 0.55)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: root.s(8)
                            anchors.rightMargin: root.s(8)
                            spacing: root.s(4)

                            Text {
                                text: "Lap " + (compactLapDelegate.sourceIndex + 1)
                                color: root.subtextColor
                                font.family: "Noto Sans"
                                font.pixelSize: root.s(8)
                                Layout.fillWidth: true
                            }
                            Text {
                                text: compactLapDelegate.lapItem
                                    ? root.formatTime(compactLapDelegate.lapItem.diff, true)
                                    : ""
                                color: root.accentColor
                                font.family: "Noto Sans"
                                font.pixelSize: root.s(8)
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }
            }

            Row {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.s(3)
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.s(80)

                RoundButton {
                    buttonSize: root.s(50)
                    label: root.stopwatchRunning ? "Lap" : "Reset"
                    enabledButton: root.stopwatchRunning || root.stopwatchMs > 0
                    onClicked: {
                        if (root.controller)
                            root.controller.clockStopwatchSecondary();
                    }
                }

                RoundButton {
                    buttonSize: root.s(50)
                    label: root.stopwatchRunning ? "Stop" : (root.stopwatchMs > 0 ? "Resume" : "Start")
                    accented: !root.stopwatchRunning
                    destructive: root.stopwatchRunning
                    onClicked: {
                        if (root.controller)
                            root.controller.clockToggle();
                    }
                }
            }
        }

        Item {
            id: pomodoroPage

            anchors.fill: parent
            enabled: root.activeMode === 2
            opacity: root.activeMode === 2 ? 1 : 0
            scale: root.activeMode === 2 ? 1 : 0.965
            x: root.activeMode === 2 ? 0 : -root.transitionDirection * root.s(12)
            visible: root.modeIsVisible(2, opacity)

            Behavior on opacity {
                NumberAnimation {
                    duration: 330
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: 390
                    easing.type: Easing.OutBack
                }
            }
            Behavior on x {
                NumberAnimation {
                    duration: 390
                    easing.type: Easing.OutCubic
                }
            }

            Item {
                anchors.fill: parent
                opacity: root.pomodoroSettingsOpen ? 0.08 : 1
                scale: root.pomodoroSettingsOpen ? 0.94 : 1

                Behavior on opacity {
                    NumberAnimation { duration: 260 }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 340
                        easing.type: Easing.OutCubic
                    }
                }

                ClockDial {
                    id: pomodoroDial

                    x: root.verticalMode ? (parent.width - width) / 2 : root.s(14)
                    y: root.verticalMode ? root.s(18) : root.s(5)
                    width: root.s(root.verticalMode ? 174 : 147)
                    height: width
                    scaleFunc: root.s
                    primaryColor: root.pomodoroState === 0 ? root.accentColor : root.greenColor
                    secondaryColor: root.pomodoroState === 0 ? root.pinkColor : root.sapphireColor
                    surfaceColor: root.surface0Color
                    textColor: root.textColor
                    subtextColor: root.subtextColor
                    progress: root.pomodoroLimitMs() > 0
                        ? root.pomodoroRemainingMs / root.pomodoroLimitMs()
                        : 0
                    mainText: root.formatTime(root.pomodoroRemainingMs, false)
                    eyebrowText: root.pomodoroPhaseLabel()
                    detailText: (root.pomodoroSessions + 1) + " of " + root.pomodoroTargetSessions
                }

                Column {
                    x: root.verticalMode ? root.s(34) : root.s(192)
                    y: root.verticalMode
                        ? pomodoroDial.y + pomodoroDial.height + root.s(14)
                        : (parent.height - height) / 2 - root.s(23)
                    width: parent.width - x - (root.verticalMode ? root.s(34) : 0)
                    spacing: root.s(9)

                    Text {
                        width: parent.width
                        text: root.pomodoroPhaseLabel()
                        color: root.textColor
                        font.family: "Noto Sans"
                        font.pixelSize: root.s(15)
                        font.weight: Font.Bold
                    }

                    Text {
                        width: parent.width
                        text: root.pomodoroState === 0
                            ? "Stay with one task until the session ends."
                            : "Breathe, move, and come back refreshed."
                        wrapMode: Text.WordWrap
                        color: root.alpha(root.subtextColor, 0.78)
                        font.family: "Noto Sans"
                        font.pixelSize: root.s(9)
                        lineHeight: 1.15
                    }

                    Row {
                        spacing: root.s(5)

                        Repeater {
                            model: root.pomodoroTargetSessions

                            Rectangle {
                                required property int index

                                width: index === root.pomodoroSessions ? root.s(16) : root.s(6)
                                height: root.s(6)
                                radius: height / 2
                                color: index <= root.pomodoroSessions
                                    ? root.accentColor
                                    : root.alpha(root.subtextColor, 0.28)

                                Behavior on width {
                                    NumberAnimation {
                                        duration: 260
                                        easing.type: Easing.OutBack
                                    }
                                }
                            }
                        }
                    }
                }

                Row {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.s(3)
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: root.s(45)

                    RoundButton {
                        buttonSize: root.s(47)
                        icon: "\uF013"
                        onClicked: root.pomodoroSettingsOpen = true
                    }

                    RoundButton {
                        buttonSize: root.s(53)
                        label: root.pomodoroRunning ? "Pause" : "Start"
                        accented: !root.pomodoroRunning
                        destructive: root.pomodoroRunning
                        onClicked: {
                            if (root.controller)
                                root.controller.clockToggle();
                        }
                    }

                    RoundButton {
                        buttonSize: root.s(47)
                        icon: "\uF051"
                        onClicked: {
                            if (root.controller)
                                root.controller.clockSkipPomodoro();
                        }
                    }
                }
            }

            Rectangle {
                id: pomodoroSettings

                anchors.centerIn: parent
                width: Math.min(parent.width - root.s(34), root.s(286))
                height: root.s(166)
                radius: root.s(22)
                color: root.alpha(root.mantleColor, 0.96)
                border.width: 1
                border.color: root.alpha(root.textColor, 0.12)
                enabled: root.pomodoroSettingsOpen
                visible: root.pomodoroSettingsOpen || opacity > 0.001
                opacity: root.pomodoroSettingsOpen ? 1 : 0
                scale: root.pomodoroSettingsOpen ? 1 : 0.82

                Behavior on opacity {
                    NumberAnimation { duration: 250 }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 370
                        easing.type: Easing.OutBack
                    }
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: root.s(13)
                    spacing: root.s(2)

                    Item {
                        width: parent.width
                        height: root.s(27)

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Pomodoro rhythm"
                            color: root.textColor
                            font.family: "Noto Sans"
                            font.pixelSize: root.s(12)
                            font.weight: Font.Bold
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\uF00D"
                            color: root.subtextColor
                            font.family: root.iconFont
                            font.pixelSize: root.s(10)

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -root.s(7)
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.pomodoroSettingsOpen = false
                            }
                        }
                    }

                    SettingRow {
                        width: parent.width
                        label: "Focus"
                        target: "pomoWorkLimit"
                        value: root.pomodoroWorkLimit
                        step: 5
                        minimum: 5
                        maximum: 60
                    }
                    SettingRow {
                        width: parent.width
                        label: "Short break"
                        target: "pomoShortBreakLimit"
                        value: root.pomodoroShortLimit
                        minimum: 1
                        maximum: 15
                    }
                    SettingRow {
                        width: parent.width
                        label: "Long break"
                        target: "pomoLongBreakLimit"
                        value: root.pomodoroLongLimit
                        step: 5
                        minimum: 5
                        maximum: 45
                    }
                    SettingRow {
                        width: parent.width
                        label: "Sessions"
                        target: "pomoTargetSessions"
                        value: root.pomodoroTargetSessions
                        minimum: 1
                        maximum: 10
                    }
                }
            }
        }

        Item {
            id: alarmModePage

            anchors.fill: parent
            enabled: root.activeMode === 3
            opacity: root.activeMode === 3 ? 1 : 0
            scale: root.activeMode === 3 ? 1 : 0.965
            x: root.activeMode === 3 ? 0 : -root.transitionDirection * root.s(12)
            visible: root.activeMode === 3

            Behavior on opacity {
                NumberAnimation {
                    duration: 330
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: 390
                    easing.type: Easing.OutBack
                }
            }
            Behavior on x {
                NumberAnimation {
                    duration: 390
                    easing.type: Easing.OutCubic
                }
            }

            AlarmSystem.AlarmView {
                id: alarmPage

                anchors.fill: parent
                scaleFunc: root.s
                baseColor: root.baseColor
                mantleColor: root.mantleColor
                surface0Color: root.surface0Color
                surface1Color: root.surface1Color
                textColor: root.textColor
                subtextColor: root.subtextColor
                accentColor: root.accentColor
                iconFont: root.iconFont
            }
        }
    }

    Rectangle {
        id: navigation

        property var navItems: [
            { mode: 3, icon: "\uF0F3", label: "Alarm" },
            { mode: 2, icon: "\uF06C", label: "Focus" },
            { mode: 1, icon: "\uF2F2", label: "Stopwatch" },
            { mode: 0, icon: "\uF252", label: "Timer" }
        ]
        property int visualIndex: {
            if (root.activeMode === 3)
                return 0;
            if (root.activeMode === 2)
                return 1;
            if (root.activeMode === 1)
                return 2;
            return 3;
        }
        property real segmentWidth: (width - root.s(8)) / 4

        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.s(8)
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - root.s(70), root.s(272))
        height: root.s(38)
        radius: height / 2
        color: root.alpha(root.surface1Color, 0.72)
        border.width: 1
        border.color: root.alpha(root.textColor, 0.10)

        Rectangle {
            x: root.s(4) + navigation.visualIndex * navigation.segmentWidth
            y: root.s(3)
            width: navigation.segmentWidth
            height: parent.height - root.s(6)
            radius: height / 2
            color: root.alpha(root.textColor, 0.13)

            Behavior on x {
                NumberAnimation {
                    duration: 390
                    easing.type: Easing.OutBack
                }
            }
        }

        Row {
            anchors.fill: parent
            anchors.margins: root.s(4)

            Repeater {
                model: navigation.navItems

                Item {
                    id: navDelegate
                    required property var modelData
                    required property int index

                    width: navigation.segmentWidth
                    height: parent.height
                    scale: navMouse.pressed ? 0.86 : 1

                    Behavior on scale {
                        NumberAnimation {
                            duration: 170
                            easing.type: Easing.OutBack
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: root.s(1)

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: navDelegate.modelData.icon
                            color: root.activeMode === navDelegate.modelData.mode
                                ? root.textColor
                                : root.alpha(root.textColor, 0.70)
                            font.family: root.iconFont
                            font.pixelSize: root.s(10)

                            Behavior on color {
                                ColorAnimation { duration: 240 }
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: root.activeMode === navDelegate.modelData.mode
                            text: navDelegate.modelData.label
                            color: root.textColor
                            font.family: "Noto Sans"
                            font.pixelSize: root.s(6)
                            font.weight: Font.DemiBold
                        }
                    }

                    MouseArea {
                        id: navMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.controller)
                                root.controller.clockSetMode(navDelegate.modelData.mode);
                        }
                    }
                }
            }
        }
    }
    }
}
