import QtQuick
import QtQuick.Controls.Basic

// The common scan settings (Image Capture's details pane): source, both
// sides, kind of picture, resolution, size, and what to do with each new
// page. Everything else is in More Options.
Rectangle {
    id: ss
    property var sheaf
    property var options: []
    property var area: null
    property bool straighten: false
    property bool crop: false
    signal areaPicked(var area)
    signal straightenToggled(bool on)
    signal cropToggled(bool on)
    signal moreOptions()
    color: Theme.sidebar

    function opt(name) {
        for (const o of options) if (o.name === name) return o
        return null
    }
    function usable(o) { return o && o.active && o.settable }
    function set(name, v) { sheaf.setOption(name, JSON.stringify(v)) }

    readonly property var source: opt("source")
    readonly property var mode: opt("mode")
    readonly property var resolution: opt("resolution")
    readonly property var duplex: {
        for (const o of options)
            if (o.type === "bool" && (/duplex/i.test(o.name) || /duplex|both sides/i.test(o.title))) return o
        return null
    }
    // The glass in millimetres (the scan area's limits).
    readonly property var glass: {
        const x = opt("br-x"), y = opt("br-y")
        if (!x || !y || !x.range || !y.range || x.unit !== "mm") return null
        return { w: x.range.max - x.range.min, h: y.range.max - y.range.min }
    }

    function modeLabel(m) {
        const s = String(m).toLowerCase()
        if (s.indexOf("color") >= 0 || s.indexOf("colour") >= 0) return "Colour"
        if (s.indexOf("gray") >= 0 || s.indexOf("grey") >= 0) return "Gray (black and white photo)"
        if (s.indexOf("lineart") >= 0 || s.indexOf("binary") >= 0 || s === "black & white" || s.indexOf("black") >= 0) return "Text (pure black and white)"
        if (s.indexOf("halftone") >= 0) return "Halftone (dots)"
        return String(m)
    }
    function sourceLabel(s) {
        const l = String(s).toLowerCase()
        if (l.indexOf("duplex") >= 0) return "Document feeder, both sides"
        if (l.indexOf("adf") >= 0 || l.indexOf("feeder") >= 0 || l.indexOf("automatic") >= 0) return "Document feeder"
        if (l.indexOf("flatbed") >= 0 || l.indexOf("normal") >= 0) return "Flatbed (glass)"
        if (l.indexOf("transparen") >= 0 || l.indexOf("tpu") >= 0) return "Film / slides"
        return String(s)
    }
    readonly property var resolutions: {
        const r = resolution
        if (!r) return []
        const common = [75, 100, 150, 200, 300, 400, 600, 1200, 2400, 4800]
        if (r.list) {
            let v = r.list.filter(x => x > 0)
            if (v.length > 12) v = v.filter(x => common.indexOf(x) >= 0)
            return v
        }
        if (r.range) return common.filter(x => x >= r.range.min && x <= r.range.max)
        return []
    }
    readonly property var sizes: {
        const out = [{ text: "Whole glass", area: null }]
        if (area) out.push({ text: "My selection", area: area, current: true })
        const g = glass
        if (g) {
            for (const p of [["A4", 210, 297], ["US Letter", 215.9, 279.4], ["US Legal", 215.9, 355.6], ["A5", 148, 210],
                             ["Photo 4×6 in", 101.6, 152.4], ["Photo 5×7 in", 127, 177.8], ["Business card", 85, 55]]) {
                if (p[1] <= g.w + 0.5 && p[2] <= g.h + 0.5)
                    out.push({ text: p[0], area: [0, 0, Math.min(1, p[1] / g.w), Math.min(1, p[2] / g.h)] })
            }
        }
        return out
    }
    readonly property string pixelsText: {
        const g = glass, r = resolution
        if (!g || !r || typeof r.value !== "number") return ""
        const a = area || [0, 0, 1, 1]
        const w = Math.round((a[2] - a[0]) * g.w / 25.4 * r.value)
        const h = Math.round((a[3] - a[1]) * g.h / 25.4 * r.value)
        const mm = Math.round((a[2] - a[0]) * g.w) + " × " + Math.round((a[3] - a[1]) * g.h) + " mm"
        return w + " × " + h + " pixels (" + mm + ")"
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + 24
        clip: true
        Column {
            id: col
            x: 14; y: 12
            width: parent.width - 28
            spacing: 6

            GLabel { text: "Scan settings"; font.pixelSize: Theme.small; font.weight: Font.DemiBold; color: Theme.fgSecondary }

            GLabel { visible: ss.usable(ss.source); text: "Source"; topPadding: 6 }
            GCombo {
                visible: ss.usable(ss.source)
                width: parent.width
                model: ss.source ? ss.source.list.map(s => ss.sourceLabel(s)) : []
                currentIndex: ss.source ? ss.source.list.indexOf(ss.source.value) : -1
                tip: "Where the pages are: on the glass (flatbed), or in the document feeder, which scans every page it holds."
                onActivated: i => ss.set("source", ss.source.list[i])
            }
            GSwitch {
                visible: ss.usable(ss.duplex)
                width: parent.width
                text: "Both sides of each sheet"
                checked: ss.duplex ? ss.duplex.value === true : false
                tip: "Scan the front and the back of each sheet in the feeder (duplex)."
                onToggled: ss.set(ss.duplex.name, checked)
            }

            GLabel { visible: ss.usable(ss.mode); text: "Kind"; topPadding: 6 }
            GCombo {
                visible: ss.usable(ss.mode)
                width: parent.width
                model: ss.mode ? ss.mode.list.map(m => ss.modeLabel(m)) : []
                currentIndex: ss.mode ? ss.mode.list.indexOf(ss.mode.value) : -1
                tip: "Colour for photos and coloured forms; Gray for most letters (smaller files); Text for crisp black-and-white text (smallest)."
                onActivated: i => ss.set("mode", ss.mode.list[i])
            }

            GLabel { visible: ss.usable(ss.resolution) && ss.resolutions.length > 0; text: "Resolution"; topPadding: 6 }
            GCombo {
                visible: ss.usable(ss.resolution) && ss.resolutions.length > 0
                width: parent.width
                model: ss.resolutions.map(r => r + " dpi" + (r === 150 ? " — screen, email" : r === 300 ? " — documents" : r === 600 ? " — photos, small print" : ""))
                currentIndex: ss.resolution ? ss.resolutions.indexOf(Math.round(ss.resolution.value)) : -1
                displayText: ss.resolution ? Math.round(ss.resolution.value) + " dpi" : ""
                tip: "Dots per inch. 300 dpi suits documents and text recognition; higher is slower and makes bigger files."
                onActivated: i => ss.set("resolution", ss.resolutions[i])
            }

            GLabel { visible: ss.glass !== null; text: "Size"; topPadding: 6 }
            GCombo {
                visible: ss.glass !== null
                width: parent.width
                model: ss.sizes.map(s => s.text)
                currentIndex: ss.area ? 1 : 0
                tip: "What part of the glass to scan. Or draw a box on the overview."
                onActivated: i => ss.areaPicked(ss.sizes[i].area)
            }
            GLabel {
                visible: ss.pixelsText !== ""
                width: parent.width
                text: ss.pixelsText
                font.pixelSize: Theme.caption
                color: Theme.fgSecondary
            }

            Rectangle { width: parent.width; height: 1; color: Theme.separator; visible: true }
            GLabel { text: "Each new page"; font.pixelSize: Theme.small; font.weight: Font.DemiBold; color: Theme.fgSecondary; topPadding: 4 }
            GCheck {
                width: parent.width
                text: "Straighten"
                checked: ss.straighten
                tip: "Turn pages that were put on the glass a little crooked, so their lines of text are level."
                onToggled: ss.straightenToggled(checked)
            }
            GCheck {
                width: parent.width
                text: "Crop to the document"
                checked: ss.crop
                tip: "Trim the empty glass around the document (or the empty border round what's on the page)."
                onToggled: ss.cropToggled(checked)
            }

            Item { width: 1; height: 6 }
            PushButton {
                width: parent.width
                text: "More Options…"
                enabled: ss.options.length > 0
                tip: Help.tip("Everything this scanner can be set to: brightness, contrast, sharpness and more.", "moreoptions")
                onClicked: ss.moreOptions()
            }
        }
    }
}
