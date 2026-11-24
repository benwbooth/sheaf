import QtQuick
import QtQuick.Controls.Basic

// macOS help tag: appears after ~0.8 s, glass, 11 pt.
ToolTip {
    id: tip
    delay: Theme.tooltipDelay
    // Drawn inside the app window: as its own popup window it came up empty
    // under arbor and sat under the pointer, swallowing the scroll wheel.
    popupType: Popup.Item
    // Below the item, like Finder's help tags, so it never covers the pointer.
    y: parent ? parent.height + 6 : 0
    timeout: 12000
    padding: 0
    topPadding: 0.001
    leftPadding: 0.001
    contentItem: GLabel {
        text: tip.text
        font.pixelSize: Theme.small
        wrapMode: Text.Wrap
        elide: Text.ElideNone
        leftPadding: 8; rightPadding: 8; topPadding: 4; bottomPadding: 4
        width: Math.min(implicitWidth, 360)
    }
    background: Rectangle {
        radius: 7
        color: Theme.glassMenu
        border.color: Theme.glassEdge
        border.width: 1
    }
    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 110 } }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 160 } }
}
