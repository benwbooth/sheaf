import QtQuick
import QtQuick.Controls.Basic

// Dialog button; `primary` is the accent-filled default.
AbstractButton {
    id: b
    property bool primary: false
    property bool destructive: false
    property string tip: ""
    implicitHeight: Math.round(26 * Theme.pt)
    implicitWidth: Math.max(Math.round(76 * Theme.pt), lbl.implicitWidth + 28)
    hoverEnabled: true
    opacity: enabled ? 1 : 0.4
    background: Rectangle {
        radius: height / 2
        color: b.primary ? (b.down ? Qt.darker(Theme.accent, 1.15) : Theme.accent)
             : b.down ? Theme.pressed : b.hovered ? Qt.rgba(Theme.field.r, Theme.field.g, Theme.field.b, Theme.field.a * 1.8) : Theme.field
        border.width: b.activeFocus ? 2 : 0
        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)
    }
    contentItem: GLabel {
        id: lbl
        text: b.text
        horizontalAlignment: Text.AlignHCenter
        color: b.primary ? Theme.accentText : b.destructive ? Theme.danger : Theme.fg
    }
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()
    GTip { visible: b.hovered && b.tip !== ""; text: b.tip }
}
