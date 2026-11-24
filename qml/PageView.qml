import QtQuick
import QtQuick.Controls.Basic

// One page up close, with the page tools: rotate, straighten, crop
// (to the content or by hand), delete, previous/next.
Rectangle {
    id: pv
    property var page: null          // {pid, path, width, height, dpi}
    property int index: -1
    property int count: 0
    property bool working: false
    property bool cropping: false
    property var cropArea: null
    signal edit(string op)
    signal remove()
    signal go(int delta)
    signal back()
    color: Theme.dark ? "#161618" : "#ececee"

    onPageChanged: { cropping = false; cropArea = null }

    Row {
        id: tools
        anchors.horizontalCenter: parent.horizontalCenter
        y: 10
        spacing: 6
        GButton { iconName: "go-previous"; enabled: pv.index > 0; tip: "Previous page  (Left)"; onClicked: pv.go(-1) }
        GLabel {
            anchors.verticalCenter: parent.verticalCenter
            text: pv.index >= 0 ? "Page " + (pv.index + 1) + " of " + pv.count : ""
            width: 110
            horizontalAlignment: Text.AlignHCenter
        }
        GButton { iconName: "go-next"; enabled: pv.index < pv.count - 1; tip: "Next page  (Right)"; onClicked: pv.go(1) }
        Rectangle { width: 1; height: 20; color: Theme.separator; anchors.verticalCenter: parent.verticalCenter }
        GButton { iconName: "object-rotate-left"; enabled: !pv.working; tip: Help.tip("Rotate left", "rotleft"); onClicked: pv.edit("rotate:-90") }
        GButton { iconName: "object-rotate-right"; enabled: !pv.working; tip: Help.tip("Rotate right", "rotright"); onClicked: pv.edit("rotate:90") }
        GButton { text: "Straighten"; enabled: !pv.working; tip: Help.tip("Level a page that was scanned a little crooked.", "straighten"); onClicked: pv.edit("straighten") }
        GButton { text: "Crop to Content"; enabled: !pv.working; tip: Help.tip("Trim the empty border around what's on the page.", "autocrop"); onClicked: pv.edit("autocrop") }
        GButton {
            text: pv.cropping ? (pv.cropArea ? "Crop" : "Drag a box…") : "Crop…"
            checked: pv.cropping
            enabled: !pv.working
            tip: Help.tip(pv.cropping ? "Cut the page down to the box you drew." : "Draw a box on the page, then click Crop to cut it down to the box.", "crop")
            onClicked: {
                if (!pv.cropping) { pv.cropping = true; return }
                if (pv.cropArea) pv.edit("crop:" + pv.cropArea.join(","))
                pv.cropping = false
                pv.cropArea = null
            }
        }
        GButton { visible: pv.cropping; text: "Cancel"; tip: "Don't crop  (Esc)"; onClicked: { pv.cropping = false; pv.cropArea = null } }
        Rectangle { width: 1; height: 20; color: Theme.separator; anchors.verticalCenter: parent.verticalCenter }
        GButton { iconName: "edit-delete"; enabled: !pv.working; tip: "Delete this page  (Delete)"; onClicked: pv.remove() }
        GButton { text: "Back to Scanner"; tip: Help.tip("Show the scanner's glass again.", "backtoscanner"); onClicked: pv.back() }
    }

    Item {
        id: area
        anchors.top: tools.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 20
        Image {
            id: img
            anchors.fill: parent
            source: pv.page ? "file://" + pv.page.path : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            // Decoded no bigger than shown (at 2× for sharpness).
            sourceSize.width: Math.min(pv.page ? pv.page.width : 4000, Math.ceil(width * 2))
            sourceSize.height: Math.min(pv.page ? pv.page.height : 4000, Math.ceil(height * 2))
            smooth: true
            mipmap: true
        }
        Rectangle {
            x: img.x + (img.width - img.paintedWidth) / 2 - 1
            y: img.y + (img.height - img.paintedHeight) / 2 - 1
            width: img.paintedWidth + 2
            height: img.paintedHeight + 2
            color: "transparent"
            border.color: Theme.separator
            z: -1
        }
        SelectionBox {
            visible: pv.cropping
            x: img.x + (img.width - img.paintedWidth) / 2
            y: img.y + (img.height - img.paintedHeight) / 2
            width: img.paintedWidth
            height: img.paintedHeight
            area: pv.cropArea
            onEdited: a => pv.cropArea = a
        }
        BusyDots {
            anchors.centerIn: parent
            running: pv.working || img.status === Image.Loading
        }
        GLabel {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: -16
            visible: pv.page !== null
            text: pv.page ? pv.page.width + " × " + pv.page.height + " pixels · " + Math.round(pv.page.dpi) + " dpi" : ""
            font.pixelSize: Theme.caption
            color: Theme.fgSecondary
        }
    }
}
