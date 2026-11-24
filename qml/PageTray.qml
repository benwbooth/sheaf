import QtQuick
import QtQuick.Controls.Basic

// The scanned pages, in document order: drag to reorder, click to select
// (Ctrl/Shift for several), double-click to look closer. Hovering a page
// shows rotate and delete buttons.
Rectangle {
    id: tray
    property ListModel pages
    property int current: -1
    signal clicked(int index, int modifiers)
    signal opened(int index)
    signal moveStep(int from, int to)
    signal dragDone(int pid, int from, int to)
    signal rotate(int index, int degrees)
    signal remove(int index)
    color: Theme.toolbar

    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.separator }

    readonly property real cardH: height - 44
    function cardW(m) { return m.height > 0 ? Math.max(40, cardH * m.width / m.height) : cardH * 0.77 }

    ListView {
        id: list
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 10
        orientation: ListView.Horizontal
        spacing: 14
        clip: true
        model: tray.pages
        boundsBehavior: Flickable.StopAtBounds
        interactive: !dragging
        property bool dragging: false
        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded; height: 8 }

        delegate: DropArea {
            id: slot
            required property int index
            required property var model
            width: tray.cardW(model)
            height: list.height
            onEntered: d => {
                const from = d.source.slotIndex
                if (from !== undefined && from !== slot.index) tray.moveStep(from, slot.index)
            }

            Item {
                id: card
                property int slotIndex: slot.index
                width: slot.width
                height: tray.cardH
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                Drag.active: ma.drag.active
                Drag.source: card
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: height / 2
                states: State {
                    when: ma.drag.active
                    ParentChange { target: card; parent: tray }
                    AnchorChanges { target: card; anchors.horizontalCenter: undefined; anchors.top: undefined }
                    PropertyChanges { card.z: 10; card.opacity: 0.85; card.scale: 1.05 }
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: 6
                    color: slot.model.selected ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : "transparent"
                    border.width: slot.model.selected ? 2 : 0
                    border.color: Theme.accent
                }
                Rectangle {
                    anchors.fill: parent
                    color: "white"
                    border.color: Theme.separator
                    Image {
                        anchors.fill: parent
                        anchors.margins: 1
                        source: slot.model.thumb ? "file://" + slot.model.thumb : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        sourceSize.height: Math.ceil(tray.cardH * 2)
                    }
                }

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    drag.target: card
                    drag.axis: Drag.XAxis
                    drag.threshold: 8
                    property int startIndex: -1
                    onPressed: startIndex = slot.index
                    onClicked: m => tray.clicked(slot.index, m.modifiers)
                    onDoubleClicked: tray.opened(slot.index)
                    drag.onActiveChanged: {
                        list.dragging = drag.active
                        if (!drag.active) {
                            if (card.slotIndex !== startIndex) tray.dragDone(slot.model.pid, startIndex, card.slotIndex)
                            card.x = 0
                        }
                    }
                }

                // Quick buttons on hover.
                Row {
                    visible: ma.containsMouse && !ma.drag.active
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 4
                    spacing: 2
                    Repeater {
                        model: [
                            { icon: "object-rotate-left", tip: Help.tip("Rotate left", "rotleft"), act: () => tray.rotate(slot.index, -90) },
                            { icon: "object-rotate-right", tip: Help.tip("Rotate right", "rotright"), act: () => tray.rotate(slot.index, 90) },
                            { icon: "edit-delete", tip: "Delete this page  (Delete)", act: () => tray.remove(slot.index) }
                        ]
                        delegate: GButton {
                            required property var modelData
                            width: 26; height: 26
                            iconName: modelData.icon
                            iconSize: 14
                            flat: false
                            tip: modelData.tip
                            background: Rectangle { radius: 6; color: Theme.glassMenu; border.color: Theme.glassEdge }
                            onClicked: modelData.act()
                        }
                    }
                }
            }
            GLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                text: (slot.index + 1)
                font.pixelSize: Theme.small
                color: slot.model.selected ? Theme.accent : Theme.fgSecondary
            }
        }
    }

    GLabel {
        visible: list.count === 0
        anchors.centerIn: parent
        text: "Scanned pages appear here. Drag them to put them in order."
        color: Theme.fgSecondary
    }
}
