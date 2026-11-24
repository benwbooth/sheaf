import QtQuick
import QtQuick.Controls.Basic

// Text field: rounded, native text, optional leading icon and clear button.
TextField {
    id: f
    property string iconName: ""
    property string tip: ""
    property bool clearable: false
    implicitHeight: Theme.controlHeight
    font.family: Theme.family
    font.pixelSize: Theme.body
    renderType: Text.NativeRendering
    color: Theme.fg
    placeholderTextColor: Theme.fgTertiary
    selectionColor: Theme.accent
    selectedTextColor: Theme.accentText
    leftPadding: iconName ? 28 : 10
    rightPadding: clearable && text ? 26 : 10
    verticalAlignment: TextInput.AlignVCenter
    hoverEnabled: true
    background: Rectangle {
        radius: height / 2
        color: Theme.field
        border.width: f.activeFocus ? 2 : 0
        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.7)
        GIcon {
            visible: f.iconName !== ""
            name: Theme.glyph(f.iconName)
            tint: Theme.fgSecondary
            size: 14
            x: 9
            anchors.verticalCenter: parent.verticalCenter
            opacity: 0.7
        }
    }
    GButton {
        visible: f.clearable && f.text !== ""
        anchors.right: parent.right
        anchors.rightMargin: 3
        anchors.verticalCenter: parent.verticalCenter
        width: 22; height: 22
        iconName: "edit-clear"
        iconSize: 12
        tip: "Clear"
        onClicked: { f.clear(); f.forceActiveFocus() }
    }
    GTip { visible: f.hovered && f.tip !== "" && !f.activeFocus; text: f.tip }
}
