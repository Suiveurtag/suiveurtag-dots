import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
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

    readonly property var categories: [
        { name: "All", icon: "󰞅" },
        { name: "Smileys & Emotion", icon: "󰈈" },
        { name: "People & Body", icon: "󰦧" },
        { name: "Animals & Nature", icon: "󰌧" },
        { name: "Food & Drink", icon: "󰆼" },
        { name: "Travel & Places", icon: "󰀻" },
        { name: "Activities", icon: "󰐱" },
        { name: "Objects", icon: "󰏗" },
        { name: "Symbols", icon: "󰫧" },
        { name: "Flags", icon: "󰈻" }
    ]
    property var allEmoji: []
    property string activeCategory: "All"
    property int activeCategoryIndex: 0
    property int pendingCategoryIndex: 0
    property int categoryDirection: 1
    property bool copied: false

    ListModel { id: emojiModel }

    Process {
        id: emojiReader
        running: true
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/emoji/emojis.json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.allEmoji = JSON.parse(this.text)
                    root.filterEmoji()
                } catch (error) {
                    console.warn("emoji-picker: invalid emoji database:", error)
                }
            }
        }
    }

    function filterEmoji() {
        let query = searchInput.text.trim().toLowerCase()
        emojiModel.clear()

        for (let i = 0; i < allEmoji.length; i++) {
            let item = allEmoji[i]
            if (activeCategory !== "All" && item.category !== activeCategory)
                continue

            let terms = (item.description + " " + item.aliases.join(" ") + " " + item.tags.join(" ")).toLowerCase()
            if (query === "" || terms.includes(query) || item.emoji.includes(query)) {
                emojiModel.append({
                    emoji: item.emoji,
                    description: item.description,
                    category: item.category
                })
            }
        }

        emojiGrid.currentIndex = emojiModel.count > 0 ? 0 : -1
        emojiGrid.positionViewAtBeginning()
    }

    function switchCategory(index) {
        if (categories.length === 0)
            return

        let wrappedIndex = (index + categories.length) % categories.length
        let referenceIndex = categorySwitchAnimation.running ? pendingCategoryIndex : activeCategoryIndex
        if (wrappedIndex === referenceIndex)
            return

        let forwardDistance = (wrappedIndex - referenceIndex + categories.length) % categories.length
        let backwardDistance = (referenceIndex - wrappedIndex + categories.length) % categories.length
        categoryDirection = forwardDistance <= backwardDistance ? 1 : -1
        pendingCategoryIndex = wrappedIndex
        categorySwitchAnimation.restart()
    }

    function switchCategoryBy(step) {
        if (categories.length === 0)
            return

        let referenceIndex = categorySwitchAnimation.running ? pendingCategoryIndex : activeCategoryIndex
        categoryDirection = step >= 0 ? 1 : -1
        pendingCategoryIndex = (referenceIndex + step + categories.length) % categories.length
        categorySwitchAnimation.restart()
    }

    function chooseEmoji(index) {
        if (index < 0 || index >= emojiModel.count)
            return

        let value = emojiModel.get(index).emoji
        Quickshell.execDetached(["wl-copy", value])
        copied = true
        closeTimer.restart()
    }

    Timer {
        id: closeTimer
        interval: 260
        onTriggered: Quickshell.execDetached([
            "bash",
            Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh",
            "close"
        ])
    }

    Timer {
        id: focusTimer
        interval: 50
        running: true
        onTriggered: searchInput.forceActiveFocus()
    }

    onVisibleChanged: {
        if (visible) {
            copied = false
            focusTimer.restart()
        } else {
            searchInput.text = ""
            activeCategory = "All"
            activeCategoryIndex = 0
        }
    }

    SequentialAnimation {
        id: categorySwitchAnimation

        ParallelAnimation {
            NumberAnimation {
                target: emojiGrid
                property: "opacity"
                to: 0
                duration: 110
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: emojiGrid
                property: "pageOffset"
                to: -root.categoryDirection * root.s(34)
                duration: 130
                easing.type: Easing.InCubic
            }
        }

        ScriptAction {
            script: {
                root.activeCategoryIndex = root.pendingCategoryIndex
                root.activeCategory = root.categories[root.activeCategoryIndex].name
                root.filterEmoji()
                emojiGrid.pageOffset = root.categoryDirection * root.s(34)
            }
        }

        ParallelAnimation {
            NumberAnimation {
                target: emojiGrid
                property: "opacity"
                to: 1
                duration: 190
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: emojiGrid
                property: "pageOffset"
                to: 0
                duration: 220
                easing.type: Easing.OutCubic
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.s(18)
        color: theme.base
        border.width: 1
        border.color: theme.surface1
        clip: true

        Rectangle {
            width: parent.width * 0.72
            height: width
            radius: width / 2
            x: -width * 0.2
            y: -height * 0.45
            color: theme.mauve
            opacity: 0.055
        }

        Rectangle {
            width: parent.width * 0.6
            height: width
            radius: width / 2
            x: parent.width - width * 0.75
            y: parent.height - height * 0.42
            color: theme.blue
            opacity: 0.045
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.s(18)
            spacing: root.s(12)

            RowLayout {
                Layout.fillWidth: true
                spacing: root.s(12)

                Text {
                    text: "󰞅"
                    color: theme.mauve
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: root.s(22)
                }

                TextField {
                    id: searchInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.s(46)
                    focus: true
                    color: theme.text
                    placeholderText: "Search emojis..."
                    placeholderTextColor: theme.subtext0
                    font.family: "JetBrains Mono"
                    font.pixelSize: root.s(14)
                    leftPadding: root.s(14)
                    rightPadding: root.s(14)
                    background: Rectangle {
                        radius: root.s(12)
                        color: theme.surface0
                        border.width: searchInput.activeFocus ? 1 : 0
                        border.color: theme.mauve
                    }

                    onTextChanged: root.filterEmoji()
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Tab) {
                            root.switchCategoryBy((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
                            event.accepted = true
                        }
                    }
                    Keys.onLeftPressed: {
                        if (emojiGrid.currentIndex > 0) emojiGrid.currentIndex--
                        event.accepted = true
                    }
                    Keys.onRightPressed: {
                        if (emojiGrid.currentIndex < emojiModel.count - 1) emojiGrid.currentIndex++
                        event.accepted = true
                    }
                    Keys.onUpPressed: {
                        emojiGrid.currentIndex = Math.max(0, emojiGrid.currentIndex - emojiGrid.columns)
                        event.accepted = true
                    }
                    Keys.onDownPressed: {
                        emojiGrid.currentIndex = Math.min(emojiModel.count - 1, emojiGrid.currentIndex + emojiGrid.columns)
                        event.accepted = true
                    }
                    Keys.onReturnPressed: {
                        root.chooseEmoji(emojiGrid.currentIndex)
                        event.accepted = true
                    }
                }

                Rectangle {
                    Layout.preferredWidth: root.s(104)
                    Layout.preferredHeight: root.s(38)
                    radius: root.s(10)
                    color: copied ? theme.green : theme.surface0

                    Text {
                        anchors.centerIn: parent
                        text: copied ? "Copied" : emojiModel.count + " emoji"
                        color: copied ? theme.crust : theme.subtext0
                        font.family: "JetBrains Mono"
                        font.pixelSize: root.s(11)
                        font.weight: Font.DemiBold
                    }

                    Behavior on color { ColorAnimation { duration: 160 } }
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: root.s(42)
                contentWidth: categoryRow.implicitWidth
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: categoryRow
                    spacing: root.s(7)

                    Repeater {
                        model: root.categories

                        Rectangle {
                            required property var modelData
                            width: categoryLabel.implicitWidth + root.s(26)
                            height: root.s(38)
                            radius: root.s(10)
                            color: root.activeCategory === modelData.name ? theme.mauve : theme.surface0

                            Text {
                                id: categoryLabel
                                anchors.centerIn: parent
                                text: modelData.icon
                                color: root.activeCategory === modelData.name ? theme.crust : theme.text
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: root.s(17)
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                    root.switchCategory(index)
                                }
                            }

                            Behavior on color { ColorAnimation { duration: 170 } }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: theme.surface1
                opacity: 0.65
            }

            GridView {
                id: emojiGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: emojiModel
                cellWidth: width / columns
                cellHeight: root.s(72)
                property int columns: 9
                property real pageOffset: 0
                boundsBehavior: Flickable.StopAtBounds
                transform: Translate { x: emojiGrid.pageOffset }
                highlightMoveDuration: 190

                onCurrentIndexChanged: {
                    if (currentIndex >= 0) positionViewAtIndex(currentIndex, GridView.Contain)
                }

                highlight: Item {
                    z: 0

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: root.s(4)
                        radius: root.s(13)
                        color: theme.mauve
                        opacity: 0.9
                        scale: 0.94

                        SequentialAnimation on scale {
                            running: emojiGrid.currentIndex >= 0
                            loops: 1
                            NumberAnimation { to: 1.04; duration: 90; easing.type: Easing.OutCubic }
                            NumberAnimation { to: 1; duration: 110; easing.type: Easing.OutBack }
                        }
                    }
                }

                delegate: Item {
                    required property int index
                    required property string emoji
                    required property string description
                    width: emojiGrid.cellWidth
                    height: emojiGrid.cellHeight
                    z: 1

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: root.s(4)
                        radius: root.s(13)
                        color: "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: emoji
                            font.family: "Noto Color Emoji"
                            font.pixelSize: root.s(31)
                            scale: index === emojiGrid.currentIndex ? 1.12 : 1
                            Behavior on scale {
                                NumberAnimation { duration: 180; easing.type: Easing.OutBack }
                            }
                        }

                        ToolTip.visible: mouse.containsMouse
                        ToolTip.text: description
                        ToolTip.delay: 450

                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: emojiGrid.currentIndex = index
                            onClicked: root.chooseEmoji(index)
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: root.s(4)
                        radius: width / 2
                        color: theme.surface2
                    }
                }
            }
        }
    }
}
