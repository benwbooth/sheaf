import QtQuick
import QtQuick.Controls.Basic

// Sheaf Help: searchable topics, and every keyboard shortcut.
Sheet {
    id: hw
    property int page: 0          // 0 topics, 1 shortcuts
    title: "Sheaf Help"
    width: Math.min(parent ? parent.width - 40 : 700, Math.round(620 * Theme.pt))

    function openAt(p) { page = p; search.text = ""; open(); search.forceActiveFocus() }

    readonly property string q: search.text.trim().toLowerCase()
    readonly property var topics: Help.topics.filter(t => q === "" || (t.title + " " + t.body).toLowerCase().indexOf(q) >= 0)
    readonly property var keys: Help.shortcuts.filter(s => q === "" || (s.action + " " + s.keys.join(" ") + " " + s.group).toLowerCase().indexOf(q) >= 0)

    Row {
        width: parent.width
        spacing: 10
        Segmented {
            model: [{ text: "Help", tip: "How to scan, fix and save pages" }, { text: "Keyboard Shortcuts", tip: "Every shortcut" }]
            current: hw.page
            onPicked: i => hw.page = i
        }
        GField {
            id: search
            width: parent.width - 260
            iconName: "edit-find|system-search"
            placeholderText: "Search help"
            clearable: true
            tip: "Find help topics and shortcuts"
        }
    }
    ListView {
        width: parent.width
        height: Math.min(contentHeight, (hw.parent ? hw.parent.height : 700) - 220)
        clip: true
        spacing: 12
        model: hw.page === 0 ? hw.topics : hw.keys
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Loader {
            required property var modelData
            width: ListView.view.width - 12
            sourceComponent: hw.page === 0 ? topicC : keyC
            property var d: modelData
        }
    }
    GLabel {
        visible: (hw.page === 0 ? hw.topics : hw.keys).length === 0
        text: "Nothing matches “" + search.text + "”."
        color: Theme.fgSecondary
    }
    Component {
        id: topicC
        Column {
            spacing: 4
            GLabel { width: parent.width; text: parent.parent.d.title; font.weight: Font.DemiBold }
            GLabel {
                width: parent.width
                text: parent.parent.d.body
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                color: Theme.fgSecondary
            }
        }
    }
    Component {
        id: keyC
        Row {
            spacing: 10
            GLabel { width: parent.parent.width * 0.62; text: parent.parent.d.action; wrapMode: Text.Wrap; elide: Text.ElideNone }
            GLabel {
                width: parent.parent.width * 0.38 - 10
                text: parent.parent.d.keys.join("  or  ")
                color: Theme.fgSecondary
                horizontalAlignment: Text.AlignRight
            }
        }
    }
    buttons: [
        PushButton { primary: true; text: "Done"; onClicked: hw.close() }
    ]
}
