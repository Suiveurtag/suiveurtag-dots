import QtQuick
import QtQuick.Layouts
import "." as AddonCards

Item {
    id: root

    property real uiScale: 1
    property int highlightedBox: -1
    property string settingsPath: ""
    property color tealColor: "#94e2d5"
    property color blueColor: "#89b4fa"
    property color mauveColor: "#cba6f7"
    property color sapphireColor: "#74c7ec"
    property color baseColor: "#1e1e2e"
    property color textColor: "#cdd6f4"
    property color subtextColor: "#a6adc8"
    property color surface0Color: "#313244"
    property color surface1Color: "#45475a"
    property color surface2Color: "#585b70"

    signal selected(int index)

    function s(value) { return value * uiScale; }
    function toggleVibrantMatugen() { vibrantCard.toggle(); }
    function toggleScreenshotFreeze() { screenshotCard.toggle(); }
    function toggleMusicVisualizer() { visualizerCard.toggle(); }
    function toggleIdleInhibit() { idleInhibitCard.toggle(); }
    function scrollToBox(index) {
        const target = index * root.s(96);
        const maximum = Math.max(0, addonsColumn.implicitHeight - addonsFlickable.height + root.s(40));
        addonsFlickable.contentY = Math.max(0, Math.min(target, maximum));
    }

    Flickable {
        id: addonsFlickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: addonsColumn.implicitHeight + root.s(80)
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: addonsColumn
            width: parent.width
            spacing: root.s(10)

            AddonCards.VibrantMatugenCard {
                id: vibrantCard
                uiScale: root.uiScale
                highlighted: root.highlightedBox === 0
                accentColor: root.tealColor
                baseColor: root.baseColor
                textColor: root.textColor
                subtextColor: root.subtextColor
                surface0Color: root.surface0Color
                surface1Color: root.surface1Color
                surface2Color: root.surface2Color
                settingsPath: root.settingsPath
                onSelected: root.selected(0)
            }

            AddonCards.ScreenshotFreezeCard {
                id: screenshotCard
                uiScale: root.uiScale
                highlighted: root.highlightedBox === 1
                accentColor: root.blueColor
                baseColor: root.baseColor
                textColor: root.textColor
                subtextColor: root.subtextColor
                surface0Color: root.surface0Color
                surface1Color: root.surface1Color
                surface2Color: root.surface2Color
                settingsPath: root.settingsPath
                onSelected: root.selected(1)
            }

            AddonCards.MusicVisualizerCard {
                id: visualizerCard
                uiScale: root.uiScale
                highlighted: root.highlightedBox === 2
                accentColor: root.mauveColor
                baseColor: root.baseColor
                textColor: root.textColor
                subtextColor: root.subtextColor
                surface0Color: root.surface0Color
                surface1Color: root.surface1Color
                surface2Color: root.surface2Color
                settingsPath: root.settingsPath
                onSelected: root.selected(2)
            }

            AddonCards.IdleInhibitCard {
                id: idleInhibitCard
                uiScale: root.uiScale
                highlighted: root.highlightedBox === 3
                accentColor: root.sapphireColor
                baseColor: root.baseColor
                textColor: root.textColor
                subtextColor: root.subtextColor
                surface0Color: root.surface0Color
                surface1Color: root.surface1Color
                surface2Color: root.surface2Color
                settingsPath: root.settingsPath
                onSelected: root.selected(3)
            }
        }
    }
}
