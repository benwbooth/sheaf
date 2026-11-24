import QtQuick
import QtQuick.Controls.Basic

// Settings, each with a line saying what it does.
Sheet {
    id: st
    property var sheaf
    property var settings: ({})
    property var languages: []
    property var folders: []
    signal changed(var settings)
    signal showWelcome()
    title: "Settings"
    width: Math.min(parent ? parent.width - 40 : 600, Math.round(540 * Theme.pt))

    function put(key, value) {
        const s = Object.assign({}, settings)
        s[key] = value
        changed(s)
    }
    onAboutToShow: {
        languages = JSON.parse(sheaf.ocrLanguages())
        folders = JSON.parse(sheaf.userFolders())
    }

    component Setting: Column {
        property string label: ""
        property string help: ""
        default property alias control: holder.data
        width: parent ? parent.width : 400
        spacing: 3
        Row {
            width: parent.width
            spacing: 10
            GLabel { text: label; width: parent.width * 0.42; anchors.verticalCenter: parent.verticalCenter; font.weight: Font.Medium }
            Item { id: holder; width: parent.width * 0.58 - 10; height: Theme.controlHeight }
        }
        GLabel {
            width: parent.width
            text: help
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            font.pixelSize: Theme.caption
            color: Theme.fgSecondary
        }
    }

    Flickable {
        width: parent.width
        height: Math.min(inner.implicitHeight, (st.parent ? st.parent.height : 700) - 220)
        contentHeight: inner.implicitHeight
        clip: true
        Column {
            id: inner
            width: parent.width - 8
            spacing: 14

            Setting {
                label: "Appearance"
                help: "Automatic follows the desktop's light or dark mode (hearth's setting)."
                GCombo {
                    anchors.fill: parent
                    model: ["Automatic", "Light", "Dark"]
                    currentIndex: ["auto", "light", "dark"].indexOf(st.settings.appearance || "auto")
                    tip: "Light or dark windows."
                    onActivated: i => st.put("appearance", ["auto", "light", "dark"][i])
                }
            }
            Setting {
                label: "Save as"
                help: "The format Save… suggests. PDF puts every page in one document."
                GCombo {
                    anchors.fill: parent
                    model: ["PDF", "PNG", "JPEG"]
                    currentIndex: ["pdf", "png", "jpeg"].indexOf(st.settings.format || "pdf")
                    tip: "The suggested file format."
                    onActivated: i => st.put("format", ["pdf", "png", "jpeg"][i])
                }
            }
            Setting {
                label: "Name"
                help: "The name Save… suggests. {date} becomes today's date, {time} the time."
                GField {
                    anchors.fill: parent
                    text: st.settings.name_pattern || ""
                    tip: "For example: Scan {date} at {time}"
                    onEditingFinished: st.put("name_pattern", text)
                }
            }
            Setting {
                label: "Save in"
                help: "The folder Save… suggests. Save… can always choose another."
                GCombo {
                    anchors.fill: parent
                    model: st.folders.map(f => f.name)
                    currentIndex: st.folders.findIndex(f => f.path === st.settings.save_folder)
                    displayText: st.settings.save_folder || ""
                    tip: "The suggested folder."
                    onActivated: i => st.put("save_folder", st.folders[i].path)
                }
            }
            Setting {
                label: "After saving"
                help: "What happens once the file is saved."
                GCombo {
                    anchors.fill: parent
                    model: ["Show it in Grove", "Open it", "Nothing"]
                    currentIndex: ["grove", "open", "nothing"].indexOf(st.settings.after_save || "grove")
                    tip: "Show the saved file in the file manager, open it, or do nothing."
                    onActivated: i => st.put("after_save", ["grove", "open", "nothing"][i])
                }
            }
            Setting {
                label: "Picture quality"
                help: "For JPEG files and the pictures inside PDFs. Higher keeps more detail; lower makes smaller files."
                Row {
                    anchors.fill: parent
                    spacing: 8
                    GSlider {
                        width: parent.width - 50
                        from: 30; to: 100; stepSize: 5
                        value: st.settings.jpeg_quality || 85
                        tip: "JPEG quality"
                        onPressedChanged: if (!pressed) st.put("jpeg_quality", Math.round(value))
                    }
                    GLabel { anchors.verticalCenter: parent.verticalCenter; text: (st.settings.jpeg_quality || 85) + "%" }
                }
            }
            Setting {
                label: "Searchable PDFs"
                help: "Recognise the words on each page when saving a PDF, so it can be searched and its text copied."
                GSwitch {
                    anchors.fill: parent
                    enabled: st.languages.length > 0
                    checked: st.settings.ocr === true
                    tip: "Text recognition (OCR) on by default in Save…"
                    onToggled: st.put("ocr", checked)
                }
            }
            Setting {
                label: "Text language"
                help: st.languages.length > 0 ? "The language text recognition reads." : "Text recognition isn't installed."
                GCombo {
                    anchors.fill: parent
                    enabled: st.languages.length > 0
                    model: st.languages
                    currentIndex: st.languages.indexOf(st.settings.ocr_language || "eng")
                    tip: "Language of the scanned text (tesseract language code)."
                    onActivated: i => st.put("ocr_language", st.languages[i])
                }
            }
            Setting {
                label: "Straighten new pages"
                help: "Level every page as it's scanned (also on the scan panel)."
                GSwitch {
                    anchors.fill: parent
                    checked: st.settings.auto_straighten === true
                    tip: "Straighten each new page automatically."
                    onToggled: st.put("auto_straighten", checked)
                }
            }
            Setting {
                label: "Crop new pages"
                help: "Trim the empty glass around each page as it's scanned (also on the scan panel)."
                GSwitch {
                    anchors.fill: parent
                    checked: st.settings.auto_crop === true
                    tip: "Crop each new page automatically."
                    onToggled: st.put("auto_crop", checked)
                }
            }
            PushButton {
                text: "Show the Welcome Tour"
                tip: "The short introduction shown the first time sheaf starts."
                onClicked: { st.close(); st.showWelcome() }
            }
        }
    }
    buttons: [
        PushButton { primary: true; text: "Done"; onClicked: st.close() }
    ]
}
