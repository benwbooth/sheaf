import QtQuick
import QtQuick.Controls.Basic

// The scanners SANE found (USB and network), like Image Capture's sidebar.
Rectangle {
    id: dl
    property var devices: []
    property string current: ""
    property bool searching: false
    property bool opening: false
    signal pick(string name)
    signal refresh()
    color: Theme.sidebar

    Column {
        id: head
        x: 12; y: 10
        width: parent.width - 24
        spacing: 4
        Item {
            width: parent.width
            height: Theme.controlHeight
            GLabel {
                anchors.verticalCenter: parent.verticalCenter
                text: "Scanners"
                font.pixelSize: Theme.small
                font.weight: Font.DemiBold
                color: Theme.fgSecondary
            }
            GButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconName: "view-refresh"
                iconSize: 14
                enabled: !dl.searching
                tip: Help.tip("Look for scanners again. Network scanners can take a few seconds to answer.", "refresh")
                onClicked: dl.refresh()
            }
        }
    }

    ListView {
        id: list
        anchors.top: head.bottom
        anchors.topMargin: 4
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 6
        clip: true
        model: dl.devices
        spacing: 2
        delegate: AbstractButton {
            id: row
            required property var modelData
            required property int index
            readonly property bool isCurrent: modelData.name === dl.current
            width: list.width
            height: Math.round(40 * Theme.pt)
            hoverEnabled: true
            background: Rectangle {
                radius: Theme.radius
                color: row.isCurrent ? Theme.accent : row.hovered ? Theme.hover : "transparent"
            }
            contentItem: Item {
                GIcon {
                    id: ic
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    size: 24
                    name: row.modelData.connection === "network" ? "printer-network|network-wireless|scanner" : "scanner|printer"
                }
                Column {
                    anchors.left: ic.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    GLabel {
                        width: parent.width
                        text: row.modelData.label
                        color: row.isCurrent ? Theme.accentText : Theme.fg
                    }
                    GLabel {
                        width: parent.width
                        text: (row.modelData.connection === "network" ? "Network" : row.modelData.connection === "usb" ? "USB" : "Scanner")
                              + (row.modelData.kind ? " · " + row.modelData.kind : "")
                        font.pixelSize: Theme.caption
                        color: row.isCurrent ? Qt.rgba(1, 1, 1, 0.8) : Theme.fgSecondary
                    }
                }
            }
            onClicked: if (!isCurrent) dl.pick(modelData.name)
            GTip {
                visible: row.hovered
                text: "Use " + row.modelData.label + "\n" + row.modelData.name
            }
        }

        // Nothing found (yet).
        Column {
            visible: list.count === 0
            width: list.width - 12
            x: 6; y: 8
            spacing: 8
            GLabel {
                width: parent.width
                text: dl.searching ? "Looking for scanners…" : "No scanners found."
                font.weight: Font.DemiBold
            }
            GLabel {
                visible: !dl.searching
                width: parent.width
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                color: Theme.fgSecondary
                font.pixelSize: Theme.small
                text: "Check that the scanner is turned on and connected (USB cable, or the same network as this computer), then click ↻.\n\nSee Help › My scanner isn't in the list."
            }
        }
    }

    BusyDots {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 12
        running: dl.searching || dl.opening
    }
}
