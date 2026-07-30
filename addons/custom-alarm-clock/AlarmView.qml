import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "." as AlarmSystem

Item {
    id: root

    property var scaleFunc: function(value) { return value; }
    property color baseColor: "#1e1e2e"
    property color mantleColor: "#181825"
    property color surface0Color: "#313244"
    property color surface1Color: "#45475a"
    property color textColor: "#cdd6f4"
    property color subtextColor: "#a6adc8"
    property color accentColor: "#cba6f7"
    property string iconFont: "Font Awesome 6 Free Solid"

    property int editorHour: 7
    property int editorMinute: 0
    property bool editorDaily: false
    property string editingId: ""
    property bool editorOpen: false

    function s(value) {
        return typeof scaleFunc === "function" ? scaleFunc(value) : value;
    }

    function alpha(color, amount) {
        return Qt.rgba(color.r, color.g, color.b, amount);
    }

    function resetEditor() {
        const next = new Date(Date.now() + 5 * 60000);
        editorHour = next.getHours();
        editorMinute = next.getMinutes();
        editorDaily = false;
        editingId = "";
        labelInput.text = "";
    }

    function openNewAlarm() {
        resetEditor();
        editorOpen = true;
    }

    function editAlarm(alarm) {
        editorHour = Number(alarm.hour);
        editorMinute = Number(alarm.minute);
        editorDaily = alarm.repeat === "daily";
        editingId = alarm.id;
        labelInput.text = alarm.label || "";
        editorOpen = true;
    }

    function closeEditor() {
        editorOpen = false;
        editorCloseTimer.restart();
    }

    function commitEditor() {
        if (!editorOpen) {
            openNewAlarm();
            return;
        }

        const label = labelInput.text.trim() || "Alarm";
        const repeatMode = editorDaily ? "daily" : "once";
        if (editingId === "") {
            AlarmSystem.AlarmManager.addAlarm(editorHour, editorMinute, label, repeatMode);
        } else {
            AlarmSystem.AlarmManager.updateAlarm(
                editingId,
                editorHour,
                editorMinute,
                label,
                repeatMode
            );
        }
        closeEditor();
    }

    component EditorStepper: Item {
        id: stepper

        property int value: 0
        property int maximum: 59
        property string label: ""
        signal valueEdited(int newValue)

        width: root.s(78)
        height: root.s(108)

        function wrapped(offset) {
            const range = maximum + 1;
            return (value + offset + range) % range;
        }

        Text {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            text: stepper.label
            color: root.alpha(root.subtextColor, 0.76)
            font.family: "Noto Sans"
            font.pixelSize: root.s(8)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.s(20)
            text: String(stepper.wrapped(-1)).padStart(2, "0")
            color: root.alpha(root.subtextColor, 0.24)
            font.family: "Noto Sans"
            font.pixelSize: root.s(18)
            font.weight: Font.DemiBold
        }

        Text {
            id: editorCurrentText

            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.s(7)
            text: String(stepper.value).padStart(2, "0")
            color: root.accentColor
            font.family: "Noto Sans"
            font.pixelSize: root.s(31)
            font.weight: Font.Bold

            SequentialAnimation {
                id: editorValuePulse

                NumberAnimation {
                    target: editorCurrentText
                    property: "scale"
                    to: 0.88
                    duration: 85
                    easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: editorCurrentText
                    property: "scale"
                    to: 1
                    duration: 175
                    easing.type: Easing.OutCubic
                }
            }
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            text: String(stepper.wrapped(1)).padStart(2, "0")
            color: root.alpha(root.subtextColor, 0.24)
            font.family: "Noto Sans"
            font.pixelSize: root.s(18)
            font.weight: Font.DemiBold
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.y < stepper.height / 2)
                    stepper.valueEdited(stepper.wrapped(-1));
                else
                    stepper.valueEdited(stepper.wrapped(1));
            }
            onWheel: wheel => {
                stepper.valueEdited(stepper.wrapped(wheel.angleDelta.y > 0 ? 1 : -1));
                wheel.accepted = true;
            }
        }

        onValueChanged: editorValuePulse.restart()
    }

    component SmallIconButton: Rectangle {
        id: iconButton

        property string icon: ""
        property color iconColor: root.textColor
        signal clicked()

        width: root.s(27)
        height: width
        radius: width / 2
        color: iconMouse.containsMouse
            ? root.alpha(root.surface1Color, 0.86)
            : "transparent"
        scale: iconMouse.pressed ? 0.86 : 1

        Behavior on scale {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }

        Text {
            anchors.centerIn: parent
            text: iconButton.icon
            color: iconButton.iconColor
            font.family: root.iconFont
            font.pixelSize: root.s(10)
        }

        MouseArea {
            id: iconMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: iconButton.clicked()
        }
    }

    Item {
        anchors.fill: parent
        opacity: root.editorOpen ? 0.10 : 1
        scale: root.editorOpen ? 0.97 : 1

        Behavior on opacity {
            NumberAnimation { duration: 220 }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 280
                easing.type: Easing.OutCubic
            }
        }

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -root.s(6)
            visible: AlarmSystem.AlarmManager.alarms.length === 0
            spacing: root.s(8)

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.s(54)
                height: root.s(82)
                radius: width / 2
                color: root.alpha(root.accentColor, 0.10)
                border.width: 1
                border.color: root.alpha(root.accentColor, 0.16)

                SequentialAnimation on scale {
                    loops: Animation.Infinite
                    running: parent.visible && !root.editorOpen
                    NumberAnimation {
                        to: 1.04
                        duration: 1800
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        to: 1
                        duration: 1800
                        easing.type: Easing.InOutSine
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "\uF0F3"
                    color: root.alpha(root.accentColor, 0.72)
                    font.family: root.iconFont
                    font.pixelSize: root.s(18)
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No alarms"
                color: root.textColor
                font.family: "Noto Sans"
                font.pixelSize: root.s(12)
                font.weight: Font.DemiBold
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Use + to create your first alarm"
                color: root.alpha(root.subtextColor, 0.72)
                font.family: "Noto Sans"
                font.pixelSize: root.s(8)
            }
        }

        ListView {
            id: alarmList

            anchors.fill: parent
            anchors.topMargin: root.s(3)
            model: AlarmSystem.AlarmManager.alarms
            spacing: root.s(6)
            clip: true

            add: Transition {
                ParallelAnimation {
                    NumberAnimation {
                        properties: "opacity"
                        from: 0
                        to: 1
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        property: "scale"
                        from: 0.90
                        to: 1
                        duration: 270
                        easing.type: Easing.OutCubic
                    }
                }
            }

            displaced: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: 230
                    easing.type: Easing.OutCubic
                }
            }

            delegate: Rectangle {
                id: alarmDelegate

                required property var modelData
                property var alarmItem: modelData

                width: alarmList.width
                height: root.s(57)
                radius: root.s(19)
                color: root.alpha(
                    root.surface0Color,
                    alarmItem.enabled === true ? 0.82 : 0.50
                )
                border.width: 1
                border.color: alarmItem.enabled === true
                    ? root.alpha(root.accentColor, 0.34)
                    : root.alpha(root.textColor, 0.07)
                opacity: alarmItem.enabled === true ? 1 : 0.62

                Behavior on opacity {
                    NumberAnimation { duration: 210 }
                }
                Behavior on color {
                    ColorAnimation { duration: 210 }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.editAlarm(alarmDelegate.alarmItem)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: root.s(13)
                    anchors.rightMargin: root.s(8)
                    spacing: root.s(9)

                    Text {
                        text: AlarmSystem.AlarmManager.formatClockTime(
                            alarmDelegate.alarmItem.hour,
                            alarmDelegate.alarmItem.minute
                        )
                        color: root.textColor
                        font.family: "Noto Sans"
                        font.pixelSize: root.s(21)
                        font.weight: Font.Bold
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            text: alarmDelegate.alarmItem.label
                            elide: Text.ElideRight
                            color: root.textColor
                            font.family: "Noto Sans"
                            font.pixelSize: root.s(9)
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: alarmDelegate.alarmItem.repeat === "daily"
                                ? "Every day"
                                : "Once"
                            color: root.subtextColor
                            font.family: "Noto Sans"
                            font.pixelSize: root.s(7)
                        }
                    }

                    Rectangle {
                        id: alarmToggle

                        width: root.s(36)
                        height: root.s(21)
                        radius: height / 2
                        color: alarmDelegate.alarmItem.enabled === true
                            ? root.accentColor
                            : root.surface1Color

                        Behavior on color {
                            ColorAnimation { duration: 190 }
                        }

                        Rectangle {
                            width: root.s(15)
                            height: width
                            radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            x: alarmDelegate.alarmItem.enabled === true
                                ? parent.width - width - root.s(3)
                                : root.s(3)
                            color: alarmDelegate.alarmItem.enabled === true
                                ? root.mantleColor
                                : root.subtextColor

                            Behavior on x {
                                NumberAnimation {
                                    duration: 190
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            z: 3
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                mouse.accepted = true;
                                AlarmSystem.AlarmManager.toggleAlarm(
                                    alarmDelegate.alarmItem.id
                                );
                            }
                        }
                    }

                    SmallIconButton {
                        icon: "\uF2ED"
                        iconColor: root.alpha(root.subtextColor, 0.80)
                        onClicked: AlarmSystem.AlarmManager.deleteAlarm(
                            alarmDelegate.alarmItem.id
                        )
                    }
                }
            }

            ScrollBar.vertical: ScrollBar {
                policy: alarmList.contentHeight > alarmList.height
                    ? ScrollBar.AsNeeded
                    : ScrollBar.AlwaysOff
            }
        }
    }

    Item {
        id: editorOverlay

        anchors.fill: parent
        enabled: root.editorOpen
        visible: root.editorOpen || opacity > 0.001
        opacity: root.editorOpen ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 220 }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeEditor()
        }

        Rectangle {
            id: editorSheet

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.min(parent.height - root.s(2), root.s(260))
            radius: root.s(24)
            color: root.alpha(root.mantleColor, 0.98)
            border.width: 1
            border.color: root.alpha(root.textColor, 0.12)
            y: root.editorOpen ? parent.height - height : parent.height + root.s(18)

            Behavior on y {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: mouse => mouse.accepted = true
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.s(13)
                spacing: root.s(7)

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        text: root.editingId === "" ? "New alarm" : "Edit alarm"
                        color: root.textColor
                        font.family: "Noto Sans"
                        font.pixelSize: root.s(13)
                        font.weight: Font.Bold
                    }

                    SmallIconButton {
                        icon: "\uF00D"
                        onClicked: root.closeEditor()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.s(108)
                    Layout.alignment: Qt.AlignHCenter
                    spacing: root.s(5)

                    Item { Layout.fillWidth: true }

                    EditorStepper {
                        value: root.editorHour
                        maximum: 23
                        label: "Hours"
                        onValueEdited: newValue => root.editorHour = newValue
                    }

                    Text {
                        text: ":"
                        color: root.textColor
                        font.family: "Noto Sans"
                        font.pixelSize: root.s(28)
                        font.weight: Font.Bold
                        Layout.alignment: Qt.AlignVCenter
                        Layout.topMargin: root.s(10)
                    }

                    EditorStepper {
                        value: root.editorMinute
                        label: "Minutes"
                        onValueEdited: newValue => root.editorMinute = newValue
                    }

                    Item { Layout.fillWidth: true }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.s(7)

                    Rectangle {
                        Layout.fillWidth: true
                        height: root.s(33)
                        radius: height / 2
                        color: root.alpha(root.surface0Color, 0.82)
                        border.width: 1
                        border.color: labelInput.activeFocus
                            ? root.alpha(root.accentColor, 0.62)
                            : root.alpha(root.textColor, 0.08)

                        TextInput {
                            id: labelInput

                            anchors.fill: parent
                            anchors.leftMargin: root.s(12)
                            anchors.rightMargin: root.s(12)
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            color: root.textColor
                            selectionColor: root.accentColor
                            selectedTextColor: root.mantleColor
                            font.family: "Noto Sans"
                            font.pixelSize: root.s(9)
                            maximumLength: 80

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: parent.text.length === 0 && !parent.activeFocus
                                text: "Alarm name"
                                color: root.alpha(root.subtextColor, 0.72)
                                font: parent.font
                            }
                        }
                    }

                    Rectangle {
                        width: root.s(70)
                        height: root.s(33)
                        radius: height / 2
                        color: root.editorDaily
                            ? root.alpha(root.accentColor, 0.36)
                            : root.alpha(root.surface1Color, 0.70)
                        border.width: 1
                        border.color: root.editorDaily
                            ? root.alpha(root.accentColor, 0.62)
                            : root.alpha(root.textColor, 0.08)

                        Text {
                            anchors.centerIn: parent
                            text: root.editorDaily ? "Daily" : "Once"
                            color: root.editorDaily ? root.accentColor : root.textColor
                            font.family: "Noto Sans"
                            font.pixelSize: root.s(8)
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.editorDaily = !root.editorDaily
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.s(7)

                    Rectangle {
                        Layout.fillWidth: true
                        height: root.s(31)
                        radius: height / 2
                        color: cancelMouse.containsMouse
                            ? root.alpha(root.surface1Color, 0.88)
                            : root.alpha(root.surface0Color, 0.74)

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: root.textColor
                            font.family: "Noto Sans"
                            font.pixelSize: root.s(9)
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.closeEditor()
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: root.s(31)
                        radius: height / 2
                        color: saveMouse.containsMouse
                            ? root.alpha(root.accentColor, 0.54)
                            : root.alpha(root.accentColor, 0.38)
                        border.width: 1
                        border.color: root.alpha(root.accentColor, 0.62)

                        Text {
                            anchors.centerIn: parent
                            text: "Save"
                            color: root.accentColor
                            font.family: "Noto Sans"
                            font.pixelSize: root.s(9)
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            id: saveMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.commitEditor()
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: editorCloseTimer

        interval: 320
        repeat: false
        onTriggered: root.resetEditor()
    }

    Shortcut {
        enabled: root.editorOpen
        sequence: "Escape"
        onActivated: root.closeEditor()
    }

    Component.onCompleted: resetEditor()
}
