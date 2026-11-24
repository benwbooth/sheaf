import QtQuick
import QtQuick.Controls.Basic

// A message at the bottom of the window, with optional buttons:
//   toast.show("Saved", [{text: "Open", run: () => ...}])
Item {
    id: toast
    property string message: ""
    property bool error: false
    property var actions: []
    width: Math.min(parent.width - 40, box.implicitWidth)
    height: box.implicitHeight
    visible: opacity > 0
    opacity: 0
    Behavior on opacity { NumberAnimation { duration: 180 } }

    function show(msg, acts, isError) {
        message = msg
        actions = acts || []
        error = isError === true
        opacity = 1
        hide.interval = actions.length ? 12000 : (error ? 9000 : 4000)
        hide.restart()
    }
    Timer { id: hide; onTriggered: toast.opacity = 0 }

    Rectangle {
        id: box
        anchors.fill: parent
        implicitWidth: row.implicitWidth + 32
        implicitHeight: Math.max(44, row.implicitHeight + 20)
        radius: Theme.glassRadius
        color: Theme.glassMenu
        border.color: toast.error ? Theme.danger : Theme.glassEdge
        border.width: 1
        HoverHandler { onHoveredChanged: if (hovered) hide.stop(); else hide.restart() }
        Row {
            id: row
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            GIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: toast.error ? "dialog-error|dialog-warning" : "dialog-information|emblem-default"
                size: 18
            }
            GLabel {
                anchors.verticalCenter: parent.verticalCenter
                text: toast.message
                width: Math.min(implicitWidth, 520)
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
            Repeater {
                model: toast.actions
                delegate: PushButton {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.text
                    tip: modelData.tip || ""
                    onClicked: { toast.opacity = 0; modelData.run() }
                }
            }
            GButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "window-close"
                iconSize: 12
                width: 24; height: 24
                tip: "Dismiss"
                onClicked: toast.opacity = 0
            }
        }
    }
}
