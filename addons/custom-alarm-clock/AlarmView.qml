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

    function s(value) {
        return typeof scaleFunc === "function" ? scaleFunc(value) : value;
    }

    function resetEditor() {
        const next = new Date(Date.now() + 5 * 60000);
        editorHour = next.getHours();
        editorMinute = next.getMinutes();
        editorDaily = false;
        editingId = "";
        labelInput.text = "";
    }

    function editAlarm(alarm) {
        editorHour = Number(alarm.hour);
        editorMinute = Number(alarm.minute);
        editorDaily = alarm.repeat === "daily";
        editingId = alarm.id;
        labelInput.text = alarm.label || "";
    }

    function commitEditor() {
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
        resetEditor();
    }

    component TimeSpinner: Column {
        property int value: 0
        property int maximum: 59
        signal valueEdited(int newValue)

        spacing: root.s(1)

        Rectangle {
            width: root.s(52)
            height: root.s(18)
            radius: root.s(5)
            color: upMouse.containsMouse ? root.surface1Color : "transparent"

            Text {
                anchors.centerIn: parent
                text: "\uF077"
                color: root.subtextColor
                font.family: root.iconFont
                font.pixelSize: root.s(9)
            }
            MouseArea {
                id: upMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: parent.parent.valueEdited((parent.parent.value + 1) % (parent.parent.maximum + 1))
            }
        }

        Text {
            width: root.s(52)
            height: root.s(32)
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: String(parent.value).padStart(2, "0")
            color: root.textColor
            font.family: "JetBrains Mono"
            font.weight: Font.Black
            font.pixelSize: root.s(24)
        }

        Rectangle {
            width: root.s(52)
            height: root.s(18)
            radius: root.s(5)
            color: downMouse.containsMouse ? root.surface1Color : "transparent"

            Text {
                anchors.centerIn: parent
                text: "\uF078"
                color: root.subtextColor
                font.family: root.iconFont
                font.pixelSize: root.s(9)
            }
            MouseArea {
                id: downMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const spinner = parent.parent;
                    spinner.valueEdited((spinner.value + spinner.maximum) % (spinner.maximum + 1));
                }
            }
        }
    }

    Rectangle {
        id: editorCard
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.s(112)
        radius: root.s(11)
        color: root.surface0Color
        border.width: 1
        border.color: root.editingId !== "" ? root.accentColor : root.surface1Color

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.s(9)
            spacing: root.s(5)

            RowLayout {
                Layout.fillWidth: true
                spacing: root.s(5)

                TimeSpinner {
                    value: root.editorHour
                    maximum: 23
                    onValueEdited: newValue => root.editorHour = newValue
                }

                Text {
                    text: ":"
                    color: root.textColor
                    font.family: "JetBrains Mono"
                    font.weight: Font.Black
                    font.pixelSize: root.s(22)
                    Layout.alignment: Qt.AlignVCenter
                }

                TimeSpinner {
                    value: root.editorMinute
                    maximum: 59
                    onValueEdited: newValue => root.editorMinute = newValue
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: root.s(36)
                    radius: root.s(8)
                    color: root.mantleColor
                    border.width: 1
                    border.color: labelInput.activeFocus ? root.accentColor : root.surface1Color

                    TextInput {
                        id: labelInput
                        anchors.fill: parent
                        anchors.leftMargin: root.s(10)
                        anchors.rightMargin: root.s(10)
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: root.textColor
                        selectionColor: root.accentColor
                        selectedTextColor: root.mantleColor
                        font.family: "JetBrains Mono"
                        font.pixelSize: root.s(11)
                        maximumLength: 80

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: parent.text.length === 0 && !parent.activeFocus
                            text: "Alarm label"
                            color: root.subtextColor
                            font: parent.font
                        }
                    }
                }

                Rectangle {
                    width: root.s(40)
                    height: root.s(40)
                    radius: root.s(10)
                    color: root.accentColor

                    Text {
                        anchors.centerIn: parent
                        text: root.editingId === "" ? "\uF067" : "\uF00C"
                        color: root.mantleColor
                        font.family: root.iconFont
                        font.pixelSize: root.s(15)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.commitEditor()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: root.s(8)

                Rectangle {
                    width: root.s(94)
                    height: root.s(24)
                    radius: height / 2
                    color: root.editorDaily ? root.accentColor : root.surface1Color

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: root.s(9)
                        anchors.rightMargin: root.s(5)
                        spacing: root.s(5)
                        Text {
                            Layout.fillWidth: true
                            text: root.editorDaily ? "Daily" : "Once"
                            color: root.editorDaily ? root.mantleColor : root.textColor
                            font.family: "JetBrains Mono"
                            font.bold: true
                            font.pixelSize: root.s(9)
                        }
                        Rectangle {
                            width: root.s(16)
                            height: width
                            radius: width / 2
                            color: root.editorDaily ? root.mantleColor : root.subtextColor
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.editorDaily = !root.editorDaily
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: {
                        const next = AlarmSystem.AlarmManager.nextAlarmText();
                        return next === "" ? "No active alarm" : "Next  " + next;
                    }
                    elide: Text.ElideRight
                    color: root.subtextColor
                    font.family: "JetBrains Mono"
                    font.pixelSize: root.s(9)
                }

                Text {
                    visible: root.editingId !== ""
                    text: "Cancel"
                    color: root.accentColor
                    font.family: "JetBrains Mono"
                    font.bold: true
                    font.pixelSize: root.s(9)

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -root.s(5)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.resetEditor()
                    }
                }
            }
        }
    }

    Item {
        anchors.top: editorCard.bottom
        anchors.topMargin: root.s(8)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        Text {
            anchors.centerIn: parent
            visible: AlarmSystem.AlarmManager.alarms.length === 0
            text: "No alarms yet"
            color: root.subtextColor
            font.family: "JetBrains Mono"
            font.pixelSize: root.s(11)
        }

        ListView {
            id: alarmList
            anchors.fill: parent
            model: AlarmSystem.AlarmManager.alarms
            spacing: root.s(6)
            clip: true

            delegate: Rectangle {
                id: alarmDelegate
                required property var modelData
                property var alarmItem: modelData

                width: alarmList.width
                height: root.s(48)
                radius: root.s(9)
                color: root.editingId === alarmItem.id ? root.surface1Color : root.surface0Color
                border.width: 1
                border.color: alarmItem.enabled === true ? root.accentColor : root.surface1Color
                opacity: alarmItem.enabled === true ? 1.0 : 0.58

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.editAlarm(parent.alarmItem)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: root.s(10)
                    anchors.rightMargin: root.s(7)
                    spacing: root.s(8)

                    Text {
                        text: AlarmSystem.AlarmManager.formatClockTime(alarmItem.hour, alarmItem.minute)
                        color: root.textColor
                        font.family: "JetBrains Mono"
                        font.weight: Font.Black
                        font.pixelSize: root.s(16)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: alarmItem.label
                            elide: Text.ElideRight
                            color: root.textColor
                            font.family: "JetBrains Mono"
                            font.bold: true
                            font.pixelSize: root.s(10)
                        }
                        Text {
                            text: alarmItem.repeat === "daily" ? "Every day" : "Once"
                            color: root.subtextColor
                            font.family: "JetBrains Mono"
                            font.pixelSize: root.s(8)
                        }
                    }

                    Rectangle {
                        width: root.s(36)
                        height: root.s(21)
                        radius: height / 2
                        color: alarmItem.enabled === true ? root.accentColor : root.surface1Color

                        Rectangle {
                            width: root.s(15)
                            height: width
                            radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            x: alarmItem.enabled === true ? parent.width - width - root.s(3) : root.s(3)
                            color: alarmItem.enabled === true ? root.mantleColor : root.subtextColor
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            z: 3
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                mouse.accepted = true;
                                AlarmSystem.AlarmManager.toggleAlarm(alarmDelegate.alarmItem.id);
                            }
                        }
                    }

                    Rectangle {
                        width: root.s(28)
                        height: width
                        radius: root.s(7)
                        color: deleteMouse.containsMouse ? root.surface1Color : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "\uF2ED"
                            color: root.subtextColor
                            font.family: root.iconFont
                            font.pixelSize: root.s(11)
                        }

                        MouseArea {
                            id: deleteMouse
                            anchors.fill: parent
                            z: 3
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                mouse.accepted = true;
                                if (root.editingId === alarmDelegate.alarmItem.id) root.resetEditor();
                                AlarmSystem.AlarmManager.deleteAlarm(alarmDelegate.alarmItem.id);
                            }
                        }
                    }
                }
            }

            ScrollBar.vertical: ScrollBar {
                policy: alarmList.contentHeight > alarmList.height
                    ? ScrollBar.AlwaysOn
                    : ScrollBar.AlwaysOff
            }
        }
    }

    Component.onCompleted: resetEditor()
}
