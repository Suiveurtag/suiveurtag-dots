import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    visible: false
    implicitWidth: Math.min(1200, screen ? screen.width : 1200)
    implicitHeight: screen ? screen.height : 800
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "serpantinum-legacy-settings"
    exclusionMode: ExclusionMode.Ignore
    focusable: visible
    Loader { anchors.fill: parent; source: "SettingsPopup.qml" }
}
