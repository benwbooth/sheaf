import QtQuick
import QtQuick.Controls.Basic

// Save the pages: name, folder, format (PDF with optional searchable
// text, PNG, JPEG), which pages.
Sheet {
    id: s
    property var sheaf
    property var settings: ({})
    property int pageCount: 0
    property int selectedCount: 0
    property bool saving: false
    property real saveProgress: 0
    property var folders: []
    property string folder: ""
    property var languages: []
    signal saveRequested(var request)
    title: "Save Scans"
    width: Math.min(parent ? parent.width - 40 : 520, Math.round(480 * Theme.pt))
    closePolicy: saving ? Popup.NoAutoClose : Popup.CloseOnEscape

    function suggestName() {
        const d = new Date()
        const pad = n => (n < 10 ? "0" : "") + n
        const date = d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
        const time = pad(d.getHours()) + "." + pad(d.getMinutes()) + "." + pad(d.getSeconds())
        return (settings.name_pattern || "Scan {date} at {time}").replace("{date}", date).replace("{time}", time)
    }
    readonly property var formats: [
        { id: "pdf", text: "PDF — one document with every page" },
        { id: "png", text: "PNG — a picture per page, full quality" },
        { id: "jpeg", text: "JPEG — a smaller picture per page" }
    ]
    readonly property string format: formats[formatBox.currentIndex] ? formats[formatBox.currentIndex].id : "pdf"
    readonly property var folderChoices: {
        const out = []
        const seen = {}
        const add = (name, path) => { if (path && !seen[path]) { seen[path] = true; out.push({ name: name, path: path }) } }
        if (folder) add(folder.split("/").pop() || folder, folder)
        for (const f of folders) add(f.name, f.path)
        out.push({ name: "Other…", path: "" })
        return out
    }

    onAboutToShow: {
        saving = false
        saveProgress = 0
        nameField.text = suggestName()
        folders = JSON.parse(sheaf.userFolders())
        folder = settings.save_folder || (folders[0] ? folders[0].path : "")
        languages = JSON.parse(sheaf.ocrLanguages())
        formatBox.currentIndex = Math.max(0, formats.findIndex(f => f.id === (settings.format || "pdf")))
        ocrCheck.checked = settings.ocr === true && languages.length > 0
        quality.value = settings.jpeg_quality || 85
        which.current = selectedCount > 0 && selectedCount < pageCount ? 1 : 0
        nameField.forceActiveFocus()
        nameField.selectAll()
    }

    GLabel { text: "Name" }
    GField {
        id: nameField
        width: parent.width
        tip: "The file's name. With several pages saved as pictures, each gets a number after it."
        onAccepted: if (saveButton.enabled) saveButton.clicked()
    }
    GLabel { text: "Where" }
    GCombo {
        id: whereBox
        width: parent.width
        model: s.folderChoices.map(f => f.name === "Other…" ? f.name : f.name + "  —  " + f.path)
        currentIndex: 0
        displayText: s.folder || "Choose a folder…"
        tip: "The folder to save in. Other… opens the folder chooser."
        onActivated: i => {
            const f = s.folderChoices[i]
            if (f.path) { s.folder = f.path; return }
            Async.call(s.sheaf, k => s.sheaf.chooseFolder(k, s.folder), r => {
                if (r.folder) s.folder = r.folder
                else if (r.error) { otherField.visible = true; otherField.text = s.folder; otherField.forceActiveFocus() }
            })
        }
    }
    GField {
        id: otherField
        visible: false
        width: parent.width
        placeholderText: "Type the folder's path"
        tip: "The desktop's folder chooser isn't available: type the folder instead."
        onTextChanged: if (visible && text) s.folder = text
    }
    GLabel { text: "Format" }
    GCombo {
        id: formatBox
        width: parent.width
        model: s.formats.map(f => f.text)
        tip: "PDF keeps every page in one document. PNG and JPEG save each page as a picture."
    }
    GCheck {
        id: ocrCheck
        visible: s.format === "pdf"
        width: parent.width
        enabled: s.languages.length > 0
        text: "Searchable text (recognise the words on the pages)"
        tip: s.languages.length > 0 ? "Reads the text on each page so you can search, select and copy it in the PDF. Takes a few seconds per page. Language: " + (s.settings.ocr_language || "eng") + " (Settings)."
                                    : "Text recognition isn't installed."
    }
    Row {
        visible: s.format !== "png"
        width: parent.width
        spacing: 10
        GLabel { text: "Quality"; anchors.verticalCenter: parent.verticalCenter }
        GSlider {
            id: quality
            width: parent.width - 140
            from: 30; to: 100; stepSize: 5
            tip: "Higher keeps more detail; lower makes smaller files. Text-only (black and white) pages are always kept exactly."
        }
        GLabel { text: Math.round(quality.value) + "%"; anchors.verticalCenter: parent.verticalCenter }
    }
    Segmented {
        id: which
        visible: s.selectedCount > 0 && s.selectedCount < s.pageCount
        model: [{ text: "All " + s.pageCount + " pages", tip: "Save every page, in order." },
                { text: "The " + s.selectedCount + " selected", tip: "Save only the pages selected in the tray." }]
        onPicked: i => which.current = i
    }
    Column {
        visible: s.saving
        width: parent.width
        spacing: 6
        GLabel { text: ocrCheck.checked && s.format === "pdf" ? "Saving and recognising text…" : "Saving…"; color: Theme.fgSecondary }
        Rectangle {
            width: parent.width; height: 6; radius: 3
            color: Theme.field
            Rectangle { width: parent.width * s.saveProgress; height: parent.height; radius: 3; color: Theme.accent }
        }
    }

    buttons: [
        PushButton {
            text: "Cancel"
            tip: s.saving ? "Stop saving" : "Don't save"
            onClicked: { if (s.saving) s.sheaf.cancelSave(); else s.close() }
        },
        PushButton {
            id: saveButton
            primary: true
            text: "Save"
            enabled: !s.saving && nameField.text.trim() !== "" && s.folder !== "" && s.pageCount > 0
            tip: "Save to " + s.folder
            onClicked: {
                s.saving = true
                s.saveRequested({ name: nameField.text.trim(), folder: s.folder, format: s.format,
                                  ocr: ocrCheck.checked && s.format === "pdf", quality: Math.round(quality.value),
                                  onlySelected: which.visible && which.current === 1 })
            }
        }
    ]
}
