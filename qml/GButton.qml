import QtQuick
import QtQuick.Controls.Basic

// Toolbar/glass button: an icon (or text), hover/pressed fills, a help tag
// saying what it does and its shortcut.
AbstractButton {
    id: b
    property string iconName: ""
    property string tip: ""
    property bool flat: true
    property bool capsule: false
    property int iconSize: 16
    property color tint: Theme.fg
    implicitHeight: Theme.controlHeight
    implicitWidth: text ? label.implicitWidth + 20 + (iconName ? iconSize + 6 : 0) : implicitHeight + 4
    hoverEnabled: true
    focusPolicy: Qt.NoFocus
    opacity: enabled ? 1 : 0.35

    background: Rectangle {
        radius: b.capsule ? height / 2 : Theme.radius
        color: b.down || b.checked ? Theme.pressed : b.hovered ? Theme.hover : (b.flat ? "transparent" : Theme.field)
        Behavior on color { ColorAnimation { duration: 90 } }
    }
    contentItem: Item {
        Row {
            anchors.centerIn: parent
            spacing: 6
            GIcon {
                visible: b.iconName !== ""
                name: Theme.glyph(b.iconName)
                tint: b.tint
                size: b.iconSize
                anchors.verticalCenter: parent.verticalCenter
            }
            GLabel {
                id: label
                visible: b.text !== ""
                text: b.text
                color: b.tint
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    GTip { visible: b.hovered && b.tip !== ""; text: b.tip }
}
