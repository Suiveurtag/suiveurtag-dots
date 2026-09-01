import QtQuick
import QtQuick.Layouts
import Quickshell
import "../reusables"

Rectangle {
    id: root

    property real uiScale: 1
    property bool highlighted: false
    property color accentColor: "#89b4fa"
    property color baseColor: "#1e1e2e"
    property color textColor: "#cdd6f4"
    property color subtextColor: "#a6adc8"
    property color surface0Color: "#313244"
    property color surface1Color: "#45475a"
    property color surface2Color: "#585b70"

    signal selected()

    function s(value) { return value * uiScale; }

    readonly property bool replaceHibernateWithLogout: {
        const all = typeof Config !== "undefined" ? Config.rawSettings : {};
        const settings = all && all.syspanel ? all.syspanel : {};
        return settings.replaceHibernateWithLogout !== false;
    }

    readonly property bool showUptime: {
        const all = typeof Config !== "undefined" ? Config.rawSettings : {};
        const settings = all && all.syspanel ? all.syspanel : {};
        return settings.showUptime !== false;
    }

    function setOption(name, value) {
        if (typeof Config === "undefined" || !Config.setSetting) return;
        let settings = Object.assign({}, Config.getSetting("syspanel", {}));
        settings[name] = value;
        Config.setSetting("syspanel", settings);
    }

    component ToggleRow : RowLayout {
        id: toggleRow
        z: 1
        property string title
        property string description
        property string settingName
        property bool checked
        signal toggled(bool value)

        Layout.fillWidth: true
        Layout.preferredHeight: s(40)
        spacing: s(12)

        ColumnLayout {
            Layout.fillWidth: true
            spacing: s(2)

            Text {
                text: toggleRow.title
                font.family: "Inter"
                font.weight: Font.Medium
                font.pixelSize: s(13)
                color: root.highlighted ? root.baseColor : root.textColor
                Layout.fillWidth: true
            }

            Text {
                text: toggleRow.description
                font.family: "Inter"
                font.pixelSize: s(10)
                color: root.highlighted ? Qt.alpha(root.baseColor, 0.72) : Qt.alpha(root.subtextColor, 0.72)
                Layout.fillWidth: true
            }
        }

        Toggle {
            id: toggleControl
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            checked: toggleRow.checked
            accentColor: root.highlighted ? root.baseColor : root.accentColor
            baseColor: root.surface1Color
            handleColor: root.highlighted ? root.accentColor : root.baseColor
            handleOffColor: root.highlighted ? root.accentColor : root.textColor
            textColor: root.highlighted ? root.baseColor : root.textColor
            toggleSound: "reusables/toggle/sfx.wav"
            onToggled: {
                if (toggleRow.settingName !== "") {
                    root.setOption(toggleRow.settingName, checked);
                }
                toggleRow.toggled(checked);
            }
        }

        MouseArea {
            id: toggleHitArea
            z: 2
            anchors.fill: toggleControl
            enabled: toggleControl.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onClicked: {
                toggleControl.checked = !toggleControl.checked;
                toggleControl.popScale = 1.05;
                toggleControl.flashOpacity = 0.2;
                togglePopAnimation.restart();
                if (typeof Sounds !== "undefined") {
                    Sounds.playSfx(toggleControl.toggleSound);
                }
                if (toggleRow.settingName !== "") {
                    root.setOption(toggleRow.settingName, toggleControl.checked);
                }
                toggleRow.toggled(toggleControl.checked);
            }
        }

        SequentialAnimation {
            id: togglePopAnimation
            NumberAnimation { target: toggleControl; property: "popScale"; to: 1.05; duration: 100; easing.type: Easing.OutQuad }
            NumberAnimation { target: toggleControl; property: "popScale"; to: 1.0; duration: 350; easing.type: Easing.OutQuint }
        }

        Connections {
            target: toggleRow
            function onCheckedChanged() {
                if (toggleControl.checked !== toggleRow.checked) {
                    toggleControl.checked = toggleRow.checked;
                }
            }
        }
    }

    Layout.fillWidth: true
    Layout.preferredHeight: contentColumn.implicitHeight + s(28)
    radius: s(12)
    color: highlighted ? accentColor : surface0Color
    border.color: highlighted ? accentColor : surface1Color
    border.width: 1

    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: root.selected()
    }

    ColumnLayout {
        id: contentColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.s(16)
        spacing: root.s(10)

        RowLayout {
            Layout.fillWidth: true
            spacing: root.s(12)

            Item {
                Layout.preferredWidth: root.s(32)
                Layout.preferredHeight: root.s(32)

                Text {
                    anchors.centerIn: parent
                    text: "󰒓"
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: root.s(16)
                    color: root.highlighted ? root.baseColor : root.accentColor
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.s(2)

                Text {
                    text: "System panel"
                    font.family: "Inter"
                    font.weight: Font.Medium
                    font.pixelSize: root.s(14)
                    color: root.highlighted ? root.baseColor : root.textColor
                }

                Text {
                    text: "Customize the power actions and header"
                    font.family: "Inter"
                    font.pixelSize: root.s(10)
                    color: root.highlighted ? Qt.alpha(root.baseColor, 0.72) : Qt.alpha(root.subtextColor, 0.72)
                }
            }
        }

        ToggleRow {
            title: "Use logout instead of hibernate"
            description: "Replace the hibernation action with session logout"
            settingName: "replaceHibernateWithLogout"
            checked: root.replaceHibernateWithLogout
        }

        ToggleRow {
            title: "Show PC uptime"
            description: "Display the current uptime at the top of the panel"
            settingName: "showUptime"
            checked: root.showUptime
        }
    }
}
