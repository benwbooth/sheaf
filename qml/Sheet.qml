import QtQuick
import QtQuick.Controls.Basic

// A modal sheet (dialog) inside the window: glass, title, body, buttons.
Popup {
    id: sh
    property string title: ""
    property string message: ""
    default property alias body: content.data
    property alias buttons: buttonRow.data
    modal: true
    focus: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(parent ? parent.width - 40 : 460, Math.round(440 * Theme.pt))
    padding: 20
    topPadding: 20.001
    leftPadding: 20.001
    closePolicy: Popup.CloseOnEscape
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, Theme.dark ? 0.35 : 0.18) }
    background: GlassPanel { tint: Theme.glassMenu; radius: Theme.windowRadius }
    contentItem: Column {
        spacing: 12
        GLabel {
            width: parent.width
            visible: sh.title !== ""
            text: sh.title
            font.bold: true
            font.pixelSize: Theme.title
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
        GLabel {
            width: parent.width
            visible: sh.message !== ""
            text: sh.message
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            color: Theme.fgSecondary
        }
        Column {
            id: content
            width: parent.width
            spacing: 10
        }
        Row {
            id: buttonRow
            anchors.right: parent.right
            spacing: 10
        }
    }
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160 }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 200; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 140 } }
}
