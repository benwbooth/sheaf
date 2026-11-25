import QtQuick
import QtQuick.Controls.Basic

// Pop-up button (macOS style): a capsule with the choice and ⌃⌄.
ComboBox {
    id: c
    property string tip: ""
    implicitHeight: Theme.controlHeight
    font.family: Theme.family
    font.pixelSize: Theme.body
    hoverEnabled: true
    background: Rectangle {
        radius: height / 2
        color: c.down ? Theme.pressed : c.hovered ? Qt.rgba(Theme.field.r, Theme.field.g, Theme.field.b, Theme.field.a * 1.8) : Theme.field
    }
    contentItem: GLabel {
        leftPadding: 12
        rightPadding: 28
        text: c.displayText
    }
    indicator: GLabel {
        x: c.width - width - 10
        anchors.verticalCenter: parent.verticalCenter
        text: "⌃⌄"
        font.pixelSize: Theme.caption
        color: Theme.fgSecondary
        rotation: 0
    }
    // The list: the shared macOS pop-up list (hearth/shared/app-menus),
    // the current choice over the button with its text lined up.
    delegate: MacComboItem { combo: c }
    popup: MacComboPopup { combo: c; dark: Theme.dark; accent: Theme.accent; textX: 12 }
    GTip { visible: c.hovered && c.tip !== "" && !c.popup.visible; text: c.tip }
}
