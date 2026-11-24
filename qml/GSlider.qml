import QtQuick
import QtQuick.Controls.Basic

Slider {
    id: s
    property string tip: ""
    hoverEnabled: true
    implicitHeight: Theme.controlHeight
    background: Rectangle {
        x: s.leftPadding
        y: s.topPadding + s.availableHeight / 2 - height / 2
        width: s.availableWidth
        height: 4
        radius: 2
        color: Theme.field
        Rectangle { width: s.visualPosition * parent.width; height: parent.height; radius: 2; color: Theme.accent }
    }
    handle: Rectangle {
        x: s.leftPadding + s.visualPosition * (s.availableWidth - width)
        y: s.topPadding + s.availableHeight / 2 - height / 2
        width: 18; height: 18; radius: 9
        color: "white"
        border.color: Theme.glassEdge
        border.width: 1
    }
    GTip { visible: s.hovered && s.tip !== "" && !s.pressed; text: s.tip }
}
