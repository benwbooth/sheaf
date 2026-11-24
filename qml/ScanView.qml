import QtQuick
import QtQuick.Controls.Basic

// The scanner's glass: the overview with the box to scan, the scan as it
// comes in, and how far it's got.
Rectangle {
    id: sv
    property var sheaf
    property var area: null           // [x0, y0, x1, y1] or null
    property real glassAspect: 8.5 / 11.7
    property bool hasDevice: false
    property bool canPreview: true
    readonly property bool busy: sheaf && sheaf.busy
    readonly property bool scanning: busy && sheaf.busyKind === "scan"
    signal areaEdited(var area)
    signal previewClicked()
    color: Theme.dark ? "#161618" : "#ececee"

    // The glass, sized to its proportions.
    Item {
        id: glassBox
        readonly property real availW: sv.width - 48
        readonly property real availH: sv.height - 48 - toolsRow.height
        readonly property real aspect: overview.status === Image.Ready ? overview.implicitWidth / Math.max(1, overview.implicitHeight) : sv.glassAspect
        width: Math.max(10, Math.min(availW, availH * aspect))
        height: Math.max(10, width / aspect)
        x: (sv.width - width) / 2
        y: 24 + (availH - height) / 2

        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            color: Theme.dark ? "#2a2a2d" : "#ffffff"
            border.color: Theme.separator
            border.width: 1
        }
        Image {
            id: overview
            anchors.fill: parent
            source: sv.sheaf ? sv.sheaf.previewUrl : ""
            fillMode: Image.Stretch
            asynchronous: true
            cache: false
            visible: !sv.scanning
            smooth: true
        }
        // The overview being made, row by row.
        Image {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            visible: sv.busy && sv.sheaf.busyKind === "preview" && status === Image.Ready
            source: sv.busy && sv.sheaf.busyKind === "preview" ? sv.sheaf.liveUrl : ""
            height: implicitWidth > 0 ? width * implicitHeight / implicitWidth : 0
            fillMode: Image.Stretch
            asynchronous: true
            cache: false
        }
        SelectionBox {
            anchors.fill: parent
            visible: !sv.scanning && sv.hasDevice
            editable: !sv.busy
            area: sv.area
            onEdited: a => sv.areaEdited(a)
        }

        // No overview yet.
        Column {
            visible: overview.status !== Image.Ready && !sv.busy
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 340)
            spacing: 12
            GIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "scanner|document-scan"
                size: 64
                opacity: 0.8
            }
            GLabel {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                text: !sv.hasDevice ? "Choose a scanner on the left."
                    : sv.canPreview ? "Put a page face down on the glass and click Overview to see it here. Then drag a box around what you want, or just click Scan."
                    : "Put your pages in the document feeder and click Scan."
                color: Theme.fgSecondary
            }
            PushButton {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: sv.hasDevice && sv.canPreview
                text: "Overview"
                tip: Help.tip("A quick, rough scan of the whole glass, to see what's there and choose what to scan.", "overview")
                onClicked: sv.previewClicked()
            }
        }
    }

    // The page being scanned, as it comes in.
    Rectangle {
        visible: sv.scanning
        anchors.fill: glassBox
        color: Theme.dark ? "#2a2a2d" : "#ffffff"
        Image {
            id: live
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            source: sv.scanning ? sv.sheaf.liveUrl : ""
            asynchronous: true
            cache: false
            readonly property real sc: implicitWidth > 0 ? parent.width / implicitWidth : 1
            width: parent.width
            height: implicitHeight * sc
            fillMode: Image.Stretch
        }
    }

    // Under the glass: what's happening and Stop.
    Row {
        id: toolsRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        height: Theme.controlHeight
        spacing: 10
        visible: sv.busy
        GLabel {
            anchors.verticalCenter: parent.verticalCenter
            text: sv.sheaf ? sv.sheaf.status : ""
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 180; height: 6; radius: 3
            color: Theme.field
            visible: sv.sheaf && sv.sheaf.progress > 0
            Rectangle {
                width: parent.width * Math.min(1, sv.sheaf ? sv.sheaf.progress : 0)
                height: parent.height
                radius: 3
                color: Theme.accent
            }
        }
        BusyDots {
            anchors.verticalCenter: parent.verticalCenter
            running: sv.busy && !(sv.sheaf && sv.sheaf.progress > 0)
        }
        PushButton {
            anchors.verticalCenter: parent.verticalCenter
            text: "Stop"
            tip: Help.tip("Stop scanning. Pages already scanned are kept.", "stop")
            onClicked: sv.sheaf.cancel()
        }
    }
}
