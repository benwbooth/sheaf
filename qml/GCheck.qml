import QtQuick
import QtQuick.Controls.Basic

CheckBox {
    id: c
    property string tip: ""
    hoverEnabled: true
    spacing: 8
    indicator: Rectangle {
        x: c.leftPadding
        anchors.verticalCenter: parent.verticalCenter
        width: 16; height: 16; radius: 4
        color: c.checked ? Theme.accent : Theme.field
        border.width: c.checked ? 0 : 1
        border.color: Theme.separator
        GLabel { anchors.centerIn: parent; text: "✓"; color: "white"; visible: c.checked; font.pixelSize: 12 }
    }
    contentItem: GLabel {
        leftPadding: c.indicator.width + c.spacing
        text: c.text
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    GTip { visible: c.hovered && c.tip !== ""; text: c.tip }
}
