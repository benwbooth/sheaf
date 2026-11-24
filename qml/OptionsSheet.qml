import QtQuick
import QtQuick.Controls.Basic

// Every option the scanner has, grouped as the scanner groups them. Hover
// an option for the scanner's own description.
Sheet {
    id: os
    property var sheaf
    property var options: []
    property bool showAdvanced: false
    signal advancedToggled(bool on)
    title: "More Scanner Options"
    message: "These depend on your scanner. Sheaf remembers your choices for it."
    width: Math.min(parent ? parent.width - 40 : 600, Math.round(560 * Theme.pt))

    function set(name, v) { sheaf.setOption(name, JSON.stringify(v)) }
    // Options shown here: not the ones on the main panel, not the scan
    // area (drawn on the overview), only single values.
    readonly property var shown: options.filter(o => {
        if (o.type === "group") return true
        if (["source", "mode", "resolution", "tl-x", "tl-y", "br-x", "br-y", "preview"].indexOf(o.name) >= 0) return false
        if (o.count > 1) return false
        if (o.advanced && !showAdvanced) return false
        return o.settable || o.type === "group"
    }).filter((o, i, a) => o.type !== "group" || (a[i + 1] && a[i + 1].type !== "group"))

    GSwitch {
        width: parent.width
        text: "Show advanced options"
        checked: os.showAdvanced
        tip: "Options the scanner marks as advanced (calibration, gamma, debugging)."
        onToggled: os.advancedToggled(checked)
    }
    ListView {
        width: parent.width
        height: Math.min(contentHeight, (os.parent ? os.parent.height : 700) - 260)
        clip: true
        model: os.shown
        spacing: 4
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Item {
            id: row
            required property var modelData
            width: ListView.view.width - 10
            height: modelData.type === "group" ? 30 : Theme.controlHeight + 6
            opacity: modelData.active ? 1 : 0.4
            HoverHandler { id: hov }
            GTip { visible: hov.hovered && row.modelData.desc !== ""; text: row.modelData.desc }
            GLabel {
                visible: row.modelData.type === "group"
                anchors.bottom: parent.bottom
                text: row.modelData.title
                font.weight: Font.DemiBold
                font.pixelSize: Theme.small
                color: Theme.fgSecondary
            }
            GLabel {
                visible: row.modelData.type !== "group" && row.modelData.type !== "button"
                width: parent.width * 0.42
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.title + (row.modelData.unit && row.modelData.unit !== "" ? " (" + row.modelData.unit + ")" : "")
            }
            Loader {
                x: parent.width * 0.45
                width: parent.width * 0.55
                anchors.verticalCenter: parent.verticalCenter
                enabled: row.modelData.active
                sourceComponent: {
                    const o = row.modelData
                    if (o.type === "bool") return boolC
                    if (o.type === "button") return buttonC
                    if (o.list) return listC
                    if ((o.type === "int" || o.type === "fixed") && o.range) return rangeC
                    if (o.type === "string" || o.type === "int" || o.type === "fixed") return textC
                    return null
                }
                property var o: row.modelData
            }
        }
    }

    Component {
        id: boolC
        GSwitch {
            checked: parent.o.value === true
            onToggled: os.set(parent.o.name, checked)
        }
    }
    Component {
        id: buttonC
        PushButton {
            text: parent.o.title
            onClicked: os.set(parent.o.name, true)
        }
    }
    Component {
        id: listC
        GCombo {
            model: parent.o.list.map(v => String(v))
            currentIndex: parent.o.list.indexOf(parent.o.value)
            onActivated: i => os.set(parent.o.name, parent.o.list[i])
        }
    }
    Component {
        id: rangeC
        Row {
            spacing: 8
            GSlider {
                id: sl
                width: parent.width - 60
                from: parent.parent.o.range.min
                to: parent.parent.o.range.max
                stepSize: parent.parent.o.range.step > 0 ? parent.parent.o.range.step : (parent.parent.o.type === "int" ? 1 : 0)
                value: typeof parent.parent.o.value === "number" ? parent.parent.o.value : from
                onPressedChanged: if (!pressed) os.set(parent.parent.o.name, value)
            }
            GLabel {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.parent.o.type === "int" ? Math.round(sl.value) : sl.value.toFixed(1)
            }
        }
    }
    Component {
        id: textC
        GField {
            text: parent.o.value === null ? "" : String(parent.o.value)
            onEditingFinished: os.set(parent.o.name, parent.o.type === "string" ? text : Number(text))
        }
    }

    buttons: [
        PushButton { primary: true; text: "Done"; onClicked: os.close() }
    ]
}
