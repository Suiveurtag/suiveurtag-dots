import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

Item {
    id: root

    property int requestedLayoutTemplate: 2
    property bool isActiveTab: typeof isCurrentTarget !== "undefined" ? isCurrentTarget : true
    property bool notesMode: false
    property string iconFont: "Font Awesome 6 Free Solid"
    property var themeColors: typeof mochaColors !== "undefined" ? mochaColors : null
    property string currentEdge: typeof activeEdge !== "undefined" ? activeEdge : "left"
    property string notePath: {
        const configured = Quickshell.env("QS_MARKDOWN_NOTES_FILE") || "";
        return configured.length > 0 ? configured : Quickshell.env("HOME") + "/Documents/Notes/quick-notes.md";
    }
    property color textColor: (typeof mochaColors !== "undefined" && mochaColors && mochaColors.text) ? mochaColors.text : "#cdd6f4"
    property color mutedColor: (typeof mochaColors !== "undefined" && mochaColors && mochaColors.subtext0) ? mochaColors.subtext0 : "#a6adc8"
    property color baseColor: (typeof mochaColors !== "undefined" && mochaColors && mochaColors.mantle) ? mochaColors.mantle : "#181825"
    property color surfaceColor: (typeof mochaColors !== "undefined" && mochaColors && mochaColors.surface0) ? mochaColors.surface0 : "#313244"
    property color activeColor: (typeof mochaColors !== "undefined" && mochaColors && mochaColors.mauve) ? mochaColors.mauve : "#cba6f7"
    property bool applyingFileText: false
    property bool dirty: false
    property string saveState: "Enregistré"

    property real preferredWidth: drawLoader.status === Loader.Ready && drawLoader.item && drawLoader.item.preferredWidth !== undefined
        ? drawLoader.item.preferredWidth : s(600)
    property real preferredExtraLength: drawLoader.status === Loader.Ready && drawLoader.item && drawLoader.item.preferredExtraLength !== undefined
        ? drawLoader.item.preferredExtraLength : s(500)
    property var interceptedShortcuts: {
        if (notesMode) return ["Tab", "Shift+Tab", "Return", "Enter", "Escape", "Left", "Right", "Up", "Down"];
        if (drawLoader.status === Loader.Ready && drawLoader.item && drawLoader.item.interceptedShortcuts !== undefined)
            return drawLoader.item.interceptedShortcuts;
        return [];
    }

    function s(value) {
        return typeof scaleFunc !== "undefined" ? scaleFunc(value) : value;
    }

    function showNotes() {
        notesMode = true;
        noteEditor.forceActiveFocus();
    }

    function showDrawing() {
        saveNow();
        notesMode = false;
    }

    function loadNote() {
        if (dirty || saveTimer.running) return;
        applyingFileText = true;
        noteEditor.text = noteFile.text();
        applyingFileText = false;
        saveState = "Enregistré";
    }

    function saveNow() {
        if (!dirty) return;
        saveTimer.stop();
        saveState = "Enregistrement…";
        noteFile.setText(noteEditor.text);
    }

    Component.onDestruction: saveNow()

    Loader {
        id: drawLoader
        anchors.fill: parent
        source: "DrawAction.qml"
        asynchronous: false
        visible: !root.notesMode

        property var scaleFunc: root.s
        property var mochaColors: root.themeColors
        property string activeEdge: root.currentEdge
        property bool isCurrentTarget: root.isActiveTab && !root.notesMode
    }

    // Floating.qml rotates the whole sidebar to follow its screen edge. Keep
    // this UI in reading orientation, just like DrawAction's own content.
    Item {
        id: orientedUiRoot
        z: 20
        anchors.centerIn: parent
        width: root.currentEdge === "bottom" ? parent.height : parent.width
        height: root.currentEdge === "bottom" ? parent.width : parent.height
        rotation: root.currentEdge === "right" ? 180 : (root.currentEdge === "bottom" ? 90 : 0)

    Rectangle {
        anchors.fill: parent
        visible: root.notesMode
        color: root.baseColor

        Column {
            anchors.fill: parent
            anchors.topMargin: root.s(62)
            anchors.leftMargin: root.s(28)
            anchors.rightMargin: root.s(28)
            anchors.bottomMargin: root.s(22)
            spacing: root.s(12)

            Row {
                width: parent.width
                height: root.s(28)
                spacing: root.s(10)

                Text {
                    text: "Bloc-notes"
                    color: root.textColor
                    font.pixelSize: root.s(18)
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: root.saveState
                    color: root.dirty ? root.activeColor : root.mutedColor
                    font.pixelSize: root.s(11)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Rectangle {
                width: parent.width
                height: parent.height - root.s(40)
                radius: root.s(16)
                color: Qt.rgba(root.surfaceColor.r, root.surfaceColor.g, root.surfaceColor.b, 0.72)
                border.width: 1
                border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.12)

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: root.s(14)
                    clip: true

                    TextArea {
                        id: noteEditor
                        width: parent.width
                        padding: root.s(8)
                        textFormat: TextEdit.PlainText
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        persistentSelection: true
                        color: root.textColor
                        selectionColor: root.activeColor
                        selectedTextColor: root.baseColor
                        font.family: "JetBrains Mono"
                        font.pixelSize: root.s(14)
                        background: null
                        placeholderText: "Écris tes notes ici…"
                        placeholderTextColor: root.mutedColor
                        onTextChanged: {
                            if (root.applyingFileText) return;
                            root.dirty = true;
                            root.saveState = "Modifié";
                            saveTimer.restart();
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: modeSwitch
        z: 100
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: root.s(12)
        width: root.s(206)
        height: root.s(38)
        radius: root.s(19)
        color: Qt.rgba(root.surfaceColor.r, root.surfaceColor.g, root.surfaceColor.b, 0.94)
        border.width: 1
        border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.14)

        Rectangle {
            width: parent.width / 2 - root.s(4)
            height: parent.height - root.s(8)
            x: root.notesMode ? parent.width / 2 : root.s(4)
            y: root.s(4)
            radius: height / 2
            color: root.activeColor
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        Row {
            anchors.fill: parent

            Repeater {
                model: [
                    { label: "Dessin", icon: "\uF303", notes: false },
                    { label: "Notes", icon: "\uF15C", notes: true }
                ]

                Item {
                    width: modeSwitch.width / 2
                    height: modeSwitch.height

                    Row {
                        anchors.centerIn: parent
                        spacing: root.s(7)

                        Text {
                            text: modelData.icon
                            font.family: root.iconFont
                            font.pixelSize: root.s(12)
                            color: root.notesMode === modelData.notes ? root.baseColor : root.textColor
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: modelData.label
                            font.pixelSize: root.s(12)
                            font.bold: root.notesMode === modelData.notes
                            color: root.notesMode === modelData.notes ? root.baseColor : root.textColor
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: modelData.notes ? root.showNotes() : root.showDrawing()
                    }
                }
            }
        }
    }
    }

    Timer {
        id: saveTimer
        interval: 650
        repeat: false
        onTriggered: root.saveNow()
    }

    FileView {
        id: noteFile
        path: root.notePath
        blockLoading: true
        atomicWrites: true
        watchChanges: true
        onLoaded: root.loadNote()
        onFileChanged: {
            if (!root.dirty && !saveTimer.running) reload();
        }
        onSaved: {
            root.dirty = false;
            root.saveState = "Enregistré";
        }
        onSaveFailed: root.saveState = "Erreur d’enregistrement"
    }
}
