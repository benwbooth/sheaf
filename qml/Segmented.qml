import QtQuick
import QtQuick.Controls.Basic

// macOS segmented control: one choice of a few. model: [{text, tip}].
Rectangle {
    id: seg
    property var model: []
    property int current: 0
    signal picked(int index)
    implicitHeight: Theme.controlHeight
    implicitWidth: row.implicitWidth + 4
    radius: height / 2
    color: Theme.field
    Row {
        id: row
        x: 2; y: 2
        height: parent.height - 4
        Repeater {
            model: seg.model
            delegate: AbstractButton {
                id: b
                required property int index
                required property var modelData
                height: row.height
                width: Math.max(lbl.implicitWidth + 24, 70)
                hoverEnabled: true
                background: Rectangle {
                    radius: height / 2
                    color: b.index === seg.current ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.18) : "#ffffff") : b.hovered ? Theme.hover : "transparent"
                    border.width: b.index === seg.current && !Theme.dark ? 1 : 0
                    border.color: Theme.separator
                }
                contentItem: GLabel {
                    id: lbl
                    text: b.modelData.text
                    horizontalAlignment: Text.AlignHCenter
                    font.weight: b.index === seg.current ? Font.DemiBold : Font.Normal
                }
                onClicked: seg.picked(b.index)
                GTip { visible: b.hovered && (b.modelData.tip || "") !== ""; text: b.modelData.tip || "" }
            }
        }
    }
}
