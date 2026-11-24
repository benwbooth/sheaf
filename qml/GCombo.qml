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
    delegate: ItemDelegate {
        id: d
        required property int index
        required property var modelData
        width: c.popup.width - 8
        height: Theme.menuRow
        highlighted: c.highlightedIndex === index
        background: Rectangle { radius: 6; color: d.highlighted ? Theme.accent : "transparent" }
        contentItem: GLabel {
            text: typeof d.modelData === "string" ? d.modelData : (d.modelData[c.textRole] || "")
            color: d.highlighted ? Theme.accentText : Theme.fg
            leftPadding: 6
        }
    }
    popup: Popup {
        y: c.height + 2
        width: Math.max(c.width, 160)
        implicitHeight: Math.min(contentItem.implicitHeight + 8, 400)
        padding: 4
        topPadding: 4.001
        leftPadding: 4.001
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: c.popup.visible ? c.delegateModel : null
            currentIndex: c.highlightedIndex
        }
        background: GlassPanel { tint: Theme.glassMenu }
    }
    GTip { visible: c.hovered && c.tip !== "" && !c.popup.visible; text: c.tip }
}
