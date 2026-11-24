import QtQuick
import QtQuick.Controls.Basic

// The first-run welcome: four steps, then off you go.
Sheet {
    id: w
    property int step: 0
    signal finished()
    readonly property var steps: [
        { icon: "scanner", title: "Welcome to Sheaf", text: "Sheaf scans documents and photos from your scanner, USB or network, and saves them as PDFs or pictures." },
        { icon: "zoom-fit-best|view-preview", title: "1. Look, then choose", text: "Pick your scanner on the left. Put a page on the glass and click Overview for a quick look, then drag a box around what you want." },
        { icon: "document-scan|scanner", title: "2. Scan", text: "Choose the kind of picture and the resolution on the right and click Scan. Scan as many pages as you like; with a document feeder, Scan does them all." },
        { icon: "document-save", title: "3. Fix and save", text: "Drag pages in the tray to reorder them; hover for rotate and delete. Then Save… makes one PDF (searchable if you like) or a picture per page." }
    ]
    title: steps[step].title
    closePolicy: Popup.NoAutoClose
    onAboutToShow: step = 0

    Row {
        width: parent.width
        spacing: 16
        GIcon { name: w.steps[w.step].icon; size: 56 }
        GLabel {
            width: parent.width - 72
            anchors.verticalCenter: parent.verticalCenter
            text: w.steps[w.step].text
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
    }
    GLabel {
        width: parent.width
        text: "Help is always in the Help menu (F1); hover over anything to see what it does."
        font.pixelSize: Theme.small
        color: Theme.fgSecondary
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    buttons: [
        PushButton { text: "Skip"; visible: w.step < w.steps.length - 1; tip: "Close the tour"; onClicked: { w.close(); w.finished() } },
        PushButton { text: "Back"; visible: w.step > 0; onClicked: w.step-- },
        PushButton {
            primary: true
            text: w.step < w.steps.length - 1 ? "Next" : "Start Scanning"
            onClicked: { if (w.step < w.steps.length - 1) w.step++; else { w.close(); w.finished() } }
        }
    ]
}
