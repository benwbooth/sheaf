import QtQuick
import QtQuick.Controls.Basic

Switch {
    id: s
    property string tip: ""
    hoverEnabled: true
    indicator: Rectangle {
        implicitWidth: 34; implicitHeight: 20
        x: s.width - width - s.rightPadding
        anchors.verticalCenter: parent.verticalCenter
        radius: 10
        color: s.checked ? Theme.accent : Theme.field
        border.width: s.checked ? 0 : 1
        border.color: Theme.separator
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle {
            x: s.checked ? parent.width - width - 2 : 2
            y: 2
            width: 16; height: 16; radius: 8
            color: "white"
            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
    }
    contentItem: GLabel { text: s.text; rightPadding: s.indicator.width + 8 }
    GTip { visible: s.hovered && s.tip !== ""; text: s.tip }
}
