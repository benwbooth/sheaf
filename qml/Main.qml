import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Window
import GlobalMenu
import Sheaf

// The scanner window: scanners on the left, the glass (overview and the
// box to scan) or one page up close in the middle, scan settings on the
// right, the scanned pages along the bottom.
ApplicationWindow {
    id: win
    // The toolbar is the title bar (the shared window chrome from
    // hearth/shared/app-menus, as in all of Ben's apps).
    flags: Qt.Window | Qt.FramelessWindowHint
    visible: true
    width: 1180
    height: 820
    minimumWidth: 760
    minimumHeight: 560
    title: device ? "Sheaf — " + deviceLabel : "Sheaf"
    color: Theme.window

    Sheaf { id: sheaf }

    // ---- state ----
    property var settings: JSON.parse(sheaf.settingsJson || "{}")
    readonly property var devices: JSON.parse(sheaf.devicesJson || "[]")
    readonly property var options: JSON.parse(sheaf.optionsJson || "[]")
    readonly property string device: sheaf.device
    readonly property string deviceLabel: {
        for (const d of devices) if (d.name === device) return d.label
        return device
    }
    property bool sidebarShown: true
    property int view: 0                       // 0 the scanner, 1 a page
    property var area: null                    // box to scan, fractions
    property int current: -1                   // the page in focus
    property var undoStack: []
    property bool dirty: false                 // pages not saved yet
    property bool pageWorking: false
    property bool autoOpened: false
    property var scanBatch: []
    readonly property bool anySheet: saveSheet.visible || optionsSheet.visible || settingsSheet.visible || helpWindow.visible || welcome.visible || closeSheet.visible || aboutSheet.visible || startOverSheet.visible
    readonly property int selectedCount: { pagesRev; let n = 0; for (let i = 0; i < pages.count; i++) if (pages.get(i).selected) n++; return n }
    property int pagesRev: 0                   // bumped when pages change

    function opt(name) { for (const o of options) if (o.name === name) return o; return null }
    readonly property bool feederSource: { const s = opt("source"); return s && s.active ? /adf|feeder|duplex|automatic/i.test(String(s.value)) : false }
    readonly property real glassAspect: {
        const x = opt("br-x"), y = opt("br-y")
        if (x && y && x.range && y.range) return (x.range.max - x.range.min) / Math.max(1, y.range.max - y.range.min)
        return 8.5 / 11.7
    }

    Binding { target: Theme; property: "mode"; value: win.settings.appearance || "auto" }
    Component.onCompleted: {
        try { Theme.hearth = JSON.parse(sheaf.env("SHEAF_HEARTH") || "{}") || {} } catch (e) {}
        sheaf.setIconTheme(Theme.dark)
        sheaf.start()
        if (!settings.welcomed && !testing) welcome.open()
        if (testing) testTimer.start()
    }
    Connections { target: Theme; function onDarkChanged() { sheaf.setIconTheme(Theme.dark) } }
    Connections {
        target: Qt.application
        function onAboutToQuit() { sheaf.clearSession() }
    }

    function putSettings(s) { sheaf.saveSettings(JSON.stringify(s)) }
    function putSetting(k, v) { const s = Object.assign({}, settings); s[k] = v; putSettings(s) }

    // ---- scanners ----
    onDevicesChanged: {
        if (autoOpened || device !== "" || devices.length === 0) return
        const last = devices.find(d => d.name === settings.last_device)
        if (last) { autoOpened = true; sheaf.openDevice(last.name) }
        else if (devices.length === 1) { autoOpened = true; sheaf.openDevice(devices[0].name) }
    }
    onDeviceChanged: area = null
    function doPreview() { if (device && !sheaf.busy) sheaf.preview() }
    function doScan() {
        if (!device || sheaf.busy) return
        scanBatch = []
        sheaf.scan(JSON.stringify({ area: area, straighten: settings.auto_straighten === true, crop: settings.auto_crop === true }))
    }
    Connections {
        target: sheaf
        function onPageScanned(json) {
            const p = JSON.parse(json)
            pages.append(win.pageRow(p, false))
            win.scanBatch.push(p.id)
            win.dirty = true
            win.pagesRev++
            win.current = pages.count - 1
        }
        function onScanFinished(json) {
            const r = JSON.parse(json)
            if (win.scanBatch.length) win.pushUndo({ kind: "add", pids: win.scanBatch.slice() })
            if (!r.ok && r.message) toast.show(r.message, [], true)
            else if (r.pages > 1) toast.show(r.pages + " pages scanned.")
        }
        function onNotify(level, message) { toast.show(message, [], level === "error") }
        function onSaveProgress(done, total) { saveSheet.saveProgress = total > 0 ? done / total : 0 }
    }

    // ---- pages ----
    ListModel { id: pages }
    function pageRow(p, selected) {
        return { pid: p.id, rev: p.rev, path: p.path, thumb: p.thumb, width: p.width, height: p.height, dpi: p.dpi, selected: selected === true }
    }
    function pageInfo(i) {
        const r = pages.get(i)
        return { id: r.pid, rev: r.rev, path: r.path, thumb: r.thumb, width: r.width, height: r.height, dpi: r.dpi }
    }
    function indexOfPid(pid) { for (let i = 0; i < pages.count; i++) if (pages.get(i).pid === pid) return i; return -1 }
    // The pages an action applies to: the selected ones, else the current.
    function targets() {
        const t = []
        for (let i = 0; i < pages.count; i++) if (pages.get(i).selected) t.push(i)
        if (!t.length && current >= 0 && current < pages.count) t.push(current)
        return t
    }
    function selectOnly(i) {
        for (let k = 0; k < pages.count; k++) pages.setProperty(k, "selected", k === i)
        current = i
        pagesRev++
    }
    function trayClick(i, mods) {
        if (mods & Qt.ControlModifier) {
            pages.setProperty(i, "selected", !pages.get(i).selected)
            current = i
        } else if ((mods & Qt.ShiftModifier) && current >= 0) {
            const a = Math.min(current, i), b = Math.max(current, i)
            for (let k = 0; k < pages.count; k++) pages.setProperty(k, "selected", k >= a && k <= b)
        } else {
            selectOnly(i)
        }
        pagesRev++
    }
    function selectAll() { for (let k = 0; k < pages.count; k++) pages.setProperty(k, "selected", true); pagesRev++ }
    function openPage(i) { if (i >= 0 && i < pages.count) { selectOnly(i); view = 1 } }

    function pushUndo(e) { const u = undoStack.slice(); u.push(e); if (u.length > 100) u.shift(); undoStack = u }
    function undo() {
        if (!undoStack.length) return
        const u = undoStack.slice()
        const e = u.pop()
        undoStack = u
        if (e.kind === "edit") {
            const i = indexOfPid(e.before.id)
            if (i >= 0) { const sel = pages.get(i).selected; pages.set(i, pageRow(e.before, sel)) }
        } else if (e.kind === "delete") {
            for (const it of e.items) pages.insert(Math.min(it.index, pages.count), pageRow(it.page, false))
        } else if (e.kind === "move") {
            const i = indexOfPid(e.pid)
            if (i >= 0) pages.move(i, e.from, 1)
        } else if (e.kind === "add") {
            for (const pid of e.pids) { const i = indexOfPid(pid); if (i >= 0) pages.remove(i) }
        }
        if (current >= pages.count) current = pages.count - 1
        dirty = pages.count > 0
        pagesRev++
    }
    readonly property string undoText: {
        if (!undoStack.length) return "Undo"
        const k = undoStack[undoStack.length - 1].kind
        return k === "edit" ? "Undo Page Change" : k === "delete" ? "Undo Delete" : k === "move" ? "Undo Move" : "Undo Scan"
    }

    function editPages(op, list) {
        const t = list || targets()
        if (!t.length || pageWorking) return
        pageWorking = true
        let left = t.length, changed = 0
        for (const i of t) {
            const before = pageInfo(i)
            Async.call(sheaf, k => sheaf.editPage(k, JSON.stringify(before), op), r => {
                if (r.error) toast.show(r.error, [], true)
                else if (!r.unchanged) {
                    const j = indexOfPid(before.id)
                    if (j >= 0) {
                        const sel = pages.get(j).selected
                        pages.set(j, pageRow(r, sel))
                        pushUndo({ kind: "edit", before: before })
                        changed++
                        dirty = true
                    }
                }
                if (--left === 0) {
                    pageWorking = false
                    pagesRev++
                    if (changed === 0 && (op === "straighten" || op === "autocrop"))
                        toast.show(op === "straighten" ? "The page already looks straight." : "There's no empty border to crop.")
                }
            })
        }
    }
    function deletePages(list) {
        const t = (list || targets()).slice().sort((a, b) => a - b)
        if (!t.length) return
        const items = t.map(i => ({ index: i, page: pageInfo(i) }))
        for (let k = t.length - 1; k >= 0; k--) pages.remove(t[k])
        pushUndo({ kind: "delete", items: items })
        if (current >= pages.count) current = pages.count - 1
        if (pages.count === 0) { view = 0; dirty = false }
        pagesRev++
    }
    function movePage(delta) {
        const i = current
        const j = i + delta
        if (i < 0 || j < 0 || j >= pages.count) return
        pages.move(i, j, 1)
        pushUndo({ kind: "move", pid: pages.get(j).pid, from: i })
        current = j
        dirty = true
        pagesRev++
    }

    // ---- saving ----
    function doSave(req) {
        const list = []
        for (let i = 0; i < pages.count; i++) if (!req.onlySelected || pages.get(i).selected) list.push(pageInfo(i))
        const s = Object.assign({}, settings)
        s.save_folder = req.folder
        s.format = req.format
        if (req.format === "pdf") s.ocr = req.ocr
        s.jpeg_quality = req.quality
        putSettings(s)
        const body = { pages: list, folder: req.folder, name: req.name, format: req.format, quality: req.quality, ocr: req.ocr, language: settings.ocr_language || "eng" }
        Async.call(sheaf, k => sheaf.save(k, JSON.stringify(body)), r => {
            saveSheet.saving = false
            if (r.cancelled) return
            if (r.error) { toast.show("Couldn't save: " + r.error, [], true); return }
            saveSheet.close()
            if (!req.onlySelected) dirty = false
            const f = r.files[0]
            const name = f.split("/").pop()
            const msg = r.files.length > 1 ? "Saved " + r.files.length + " files in " + req.folder.split("/").pop() + "." : "Saved “" + name + "”."
            toast.show(msg, [{ text: "Open", tip: "Open it in its app", run: () => sheaf.openFile(f) },
                             { text: "Show in Grove", tip: "Show it in its folder", run: () => sheaf.showInFileManager(f) }])
            if (settings.after_save === "open") sheaf.openFile(f)
            else if ((settings.after_save || "grove") === "grove") sheaf.showInFileManager(f)
            if (afterSaveQuit) Qt.quit()
        })
    }
    property bool afterSaveQuit: false

    // ---- closing ----
    property bool reallyClose: false
    onClosing: close => {
        if (dirty && pages.count > 0 && !reallyClose && !testing) { close.accepted = false; closeSheet.open() }
    }

    // ---- menus (global menu bar + ☰) ----
    function mk(id, text, icon, enabled) { return { id: id, text: text, icon: icon, enabled: enabled !== false, shortcut: Help.key(id) } }
    readonly property bool hasPages: pages.count > 0
    readonly property bool hasTargets: { pagesRev; return selectedCount > 0 || (current >= 0 && current < pages.count) }
    readonly property var menuModel: [
        { title: "Sheaf", items: [
            mk("about", "About Sheaf", "help-about"),
            { separator: true },
            mk("settings", "Settings…", "preferences-system|configure"),
            { separator: true },
            mk("quit", "Quit Sheaf", "application-exit")
        ] },
        { title: "File", items: [
            mk("save", "Save…", "document-save", hasPages && !sheaf.busy),
            { separator: true },
            mk("startover", "Start Over…", "document-new", hasPages),
            { separator: true },
            mk("close", "Close Window", "window-close")
        ] },
        { title: "Edit", items: [
            mk("undo", undoText, "edit-undo", undoStack.length > 0),
            { separator: true },
            mk("selectall", "Select All Pages", "edit-select-all", hasPages),
            mk("delete", "Delete Pages", "edit-delete", hasTargets)
        ] },
        { title: "Scanner", items: [
            mk("overview", "Overview", "zoom-fit-best|view-preview", device !== "" && !sheaf.busy && !feederSource),
            mk("scan", "Scan", "document-scan|scanner", device !== "" && !sheaf.busy),
            mk("stop", "Stop", "process-stop", sheaf.busy),
            { separator: true },
            mk("detect", "Select the Document", "transform-crop|image-crop", sheaf.previewBounds !== "" && !sheaf.busy),
            mk("wholearea", "Whole Glass", "zoom-fit-page|zoom-original", area !== null),
            { separator: true },
            mk("moreoptions", "More Options…", "configure|preferences-system", options.length > 0),
            mk("refresh", "Look for Scanners Again", "view-refresh", !sheaf.searching)
        ] },
        { title: "Page", items: [
            mk("rotleft", "Rotate Left", "object-rotate-left", hasTargets && !pageWorking),
            mk("rotright", "Rotate Right", "object-rotate-right", hasTargets && !pageWorking),
            mk("straighten", "Straighten", "object-straighten|transform-rotate", hasTargets && !pageWorking),
            mk("autocrop", "Crop to Content", "transform-crop|image-crop", hasTargets && !pageWorking),
            { separator: true },
            mk("moveup", "Move Earlier", "go-previous", current > 0),
            mk("movedown", "Move Later", "go-next", current >= 0 && current < pages.count - 1),
            { separator: true },
            mk("pagesview", "Look at the Page", "zoom-in", current >= 0),
            mk("backtoscanner", "Back to the Scanner", "scanner", view !== 0)
        ] },
        { title: "View", items: [
            Object.assign(mk("sidebar", "Scanner List", "sidebar-show|view-left-pane"), { checkable: true, checked: sidebarShown })
        ] },
        { title: "Help", items: [
            mk("help", "Sheaf Help", "help-contents|help-about"),
            mk("shortcutlist", "Keyboard Shortcuts", "input-keyboard|preferences-desktop-keyboard"),
            mk("welcome", "Welcome Tour", "help-hint|help-about")
        ] }
    ]
    function act(id) {
        switch (id) {
        case "about": aboutSheet.open(); break
        case "settings": settingsSheet.open(); break
        case "quit": Qt.quit(); break
        case "save": if (hasPages && !sheaf.busy) saveSheet.open(); break
        case "startover": if (hasPages) startOverSheet.open(); break
        case "close": win.close(); break
        case "undo": undo(); break
        case "selectall": selectAll(); break
        case "delete": deletePages(); break
        case "overview": if (!feederSource) doPreview(); break
        case "scan": doScan(); break
        case "stop": sheaf.cancel(); break
        case "detect": if (sheaf.previewBounds) area = JSON.parse(sheaf.previewBounds); break
        case "wholearea": area = null; break
        case "moreoptions": if (options.length) optionsSheet.open(); break
        case "refresh": sheaf.refreshDevices(); break
        case "rotleft": editPages("rotate:-90"); break
        case "rotright": editPages("rotate:90"); break
        case "straighten": editPages("straighten"); break
        case "autocrop": editPages("autocrop"); break
        case "crop": if (current >= 0) { view = 1; pageView.cropping = true } break
        case "moveup": movePage(-1); break
        case "movedown": movePage(1); break
        case "pagesview": if (current >= 0) view = 1; break
        case "backtoscanner": view = 0; break
        case "sidebar": sidebarShown = !sidebarShown; break
        case "help": helpWindow.openAt(0); break
        case "shortcutlist": helpWindow.openAt(1); break
        case "welcome": welcome.open(); break
        }
    }
    GlobalMenuBar { id: globalMenu; window: win; model: win.menuModel; onTriggered: id => win.act(id) }
    onVisibleChanged: if (visible) Qt.callLater(globalMenu.attach)
    AppMenu {
        id: appMenu
        model: win.menuModel
        onTriggered: id => win.act(id)
        accent: Theme.accent
        dark: Theme.dark
        popupType: Popup.Item
    }

    // ---- keyboard ----
    Repeater {
        model: ["about", "settings", "quit", "save", "startover", "close", "undo", "selectall", "overview", "scan", "detect", "wholearea",
                "moreoptions", "refresh", "rotleft", "rotright", "straighten", "autocrop", "crop", "moveup", "movedown", "backtoscanner",
                "pagesview", "sidebar", "help", "shortcutlist"]
        delegate: Item {
            required property string modelData
            Shortcut {
                sequences: (Help.entry(parent.modelData) || { keys: [] }).keys
                enabled: !win.anySheet
                onActivated: win.act(parent.modelData)
            }
        }
    }
    Shortcut { sequences: ["Delete", "Backspace"]; enabled: !win.anySheet && !pageView.cropping; onActivated: win.deletePages() }
    Shortcut { sequence: "Esc"; enabled: !win.anySheet; onActivated: { if (pageView.cropping) pageView.cropping = false; else if (sheaf.busy) sheaf.cancel(); else if (win.view === 1) win.view = 0 } }
    Shortcut { sequence: "Return"; enabled: !win.anySheet && win.view === 0 && win.current >= 0; onActivated: win.view = 1 }
    Shortcut { sequence: "Left"; enabled: !win.anySheet && win.current > 0; onActivated: win.selectOnly(win.current - 1) }
    Shortcut { sequence: "Right"; enabled: !win.anySheet && win.current < pages.count - 1; onActivated: win.selectOnly(win.current + 1) }

    // ---- the window ----
    Item {
        id: shell
        anchors.fill: parent
        // A thousandth of a pixel: text never lands exactly on a half
        // device pixel at 130% (round letters dropped a pixel).
        anchors.topMargin: 0.001
        transform: Translate { x: 0.001 }

        // Toolbar.
        Rectangle {
            id: toolbar
            width: parent.width
            height: Theme.toolbarHeight
            color: Theme.toolbar
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.separator }
            // Drag to move, double-click to maximize, right-click for the
            // window menu; minimize, maximize and close at the right end.
            ChromeTitleArea { anchors.fill: parent; window: win; menuDark: Theme.dark; menuAccent: Theme.accent }
            ChromeButtons {
                id: winButtons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                window: win
                fg: Theme.fg
                bg: Theme.toolbar
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                GButton {
                    iconName: "sidebar-show|view-left-pane|view-sidetree"
                    checked: win.sidebarShown
                    tip: Help.tip("Show or hide the scanner list", "sidebar")
                    onClicked: win.sidebarShown = !win.sidebarShown
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    GLabel { text: win.device ? win.deviceLabel : "Sheaf"; font.weight: Font.DemiBold; width: Math.min(implicitWidth, 260) }
                    GLabel {
                        text: sheaf.busy || sheaf.opening ? sheaf.status : win.device ? (win.feederSource ? "Document feeder" : "Ready") : "No scanner chosen"
                        font.pixelSize: Theme.caption
                        color: Theme.fgSecondary
                        width: Math.min(implicitWidth, 260)
                    }
                }
            }
            Segmented {
                anchors.centerIn: parent
                model: [{ text: "Scanner", tip: Help.tip("The scanner's glass: overview, selection and settings", "backtoscanner") },
                        { text: pages.count ? "Pages (" + pages.count + ")" : "Pages", tip: Help.tip("Look at the selected page up close and fix it", "pagesview") }]
                current: win.view
                onPicked: i => { if (i === 1 && win.current < 0 && pages.count) win.selectOnly(0); win.view = (i === 1 && pages.count === 0) ? 0 : i }
            }
            Row {
                anchors.right: winButtons.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                GButton {
                    text: "Overview"
                    iconName: "zoom-fit-best|view-preview"
                    enabled: win.device !== "" && !sheaf.busy && !win.feederSource
                    tip: win.feederSource ? "An overview needs the flatbed: choose it under Source." : Help.tip("A quick, rough scan of the whole glass, to see what's there and choose what to scan.", "overview")
                    onClicked: win.doPreview()
                }
                PushButton {
                    primary: true
                    text: sheaf.busy && sheaf.busyKind === "scan" ? "Scanning…" : "Scan"
                    enabled: win.device !== "" && !sheaf.busy
                    tip: Help.tip(win.feederSource ? "Scan every page in the document feeder." : win.area ? "Scan the part of the glass inside the box." : "Scan the whole glass.", "scan")
                    onClicked: win.doScan()
                }
                PushButton {
                    text: "Save…"
                    enabled: pages.count > 0 && !sheaf.busy
                    tip: Help.tip("Save the pages as a PDF or as pictures.", "save")
                    onClicked: saveSheet.open()
                }
                GButton {
                    id: menuButton
                    iconName: "overflow-menu-symbolic|view-more-symbolic|application-menu"
                    tip: "All menus (also in the menu bar at the top of the screen)"
                    onClicked: appMenu.openBelow(menuButton)
                }
                GButton {
                    iconName: "help-contents|help-about"
                    tip: Help.tip("Sheaf Help", "help")
                    onClicked: helpWindow.openAt(0)
                }
            }
        }

        // Body.
        Item {
            id: body
            anchors.top: toolbar.bottom
            anchors.bottom: tray.top
            width: parent.width

            DeviceList {
                id: deviceList
                visible: win.sidebarShown
                width: visible ? Math.round(220 * Theme.pt) : 0
                height: parent.height
                devices: win.devices
                current: win.device
                searching: sheaf.searching
                opening: sheaf.opening
                onPick: name => sheaf.openDevice(name)
                onRefresh: sheaf.refreshDevices()
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.separator }
            }
            ScanView {
                visible: win.view === 0
                anchors.left: deviceList.right
                anchors.right: scanSettings.left
                height: parent.height
                sheaf: sheaf
                area: win.area
                glassAspect: win.glassAspect
                hasDevice: win.device !== "" && !sheaf.opening
                canPreview: !win.feederSource
                onAreaEdited: a => win.area = a
                onPreviewClicked: win.doPreview()
            }
            PageView {
                id: pageView
                visible: win.view === 1
                anchors.left: deviceList.right
                anchors.right: parent.right
                height: parent.height
                index: win.current
                count: pages.count
                page: { win.pagesRev; return win.current >= 0 && win.current < pages.count ? pages.get(win.current) : null }
                working: win.pageWorking
                onEdit: op => win.editPages(op, [win.current])
                onRemove: win.deletePages([win.current])
                onGo: d => win.selectOnly(Math.max(0, Math.min(pages.count - 1, win.current + d)))
                onBack: win.view = 0
            }
            ScanSettings {
                id: scanSettings
                visible: win.view === 0
                anchors.right: parent.right
                width: visible ? Math.round(270 * Theme.pt) : 0
                height: parent.height
                sheaf: sheaf
                options: win.options
                area: win.area
                straighten: win.settings.auto_straighten === true
                crop: win.settings.auto_crop === true
                enabled: !sheaf.busy && win.device !== ""
                onAreaPicked: a => win.area = a
                onStraightenToggled: on => win.putSetting("auto_straighten", on)
                onCropToggled: on => win.putSetting("auto_crop", on)
                onMoreOptions: optionsSheet.open()
                Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: Theme.separator }
            }
        }

        PageTray {
            id: tray
            anchors.bottom: parent.bottom
            width: parent.width
            height: Math.round(150 * Theme.pt)
            pages: pages
            onClicked: (i, m) => win.trayClick(i, m)
            onOpened: i => win.openPage(i)
            onMoveStep: (from, to) => { pages.move(from, to, 1); win.current = to; win.pagesRev++ }
            onDragDone: (pid, from, to) => { win.pushUndo({ kind: "move", pid: pid, from: from }); win.dirty = true }
            onRotate: (i, d) => win.editPages("rotate:" + d, [i])
            onRemove: i => win.deletePages([i])
        }

        Toast {
            id: toast
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: tray.top
            anchors.bottomMargin: 16
            z: 20
        }
    }

    // ---- sheets ----
    SaveSheet {
        id: saveSheet
        sheaf: sheaf
        settings: win.settings
        pageCount: pages.count
        selectedCount: win.selectedCount
        onSaveRequested: req => win.doSave(req)
    }
    OptionsSheet {
        id: optionsSheet
        sheaf: sheaf
        options: win.options
        showAdvanced: win.settings.show_advanced === true
        onAdvancedToggled: on => win.putSetting("show_advanced", on)
    }
    SettingsSheet {
        id: settingsSheet
        sheaf: sheaf
        settings: win.settings
        onChanged: s => win.putSettings(s)
        onShowWelcome: welcome.open()
    }
    HelpWindow { id: helpWindow }
    Welcome {
        id: welcome
        onFinished: if (!win.settings.welcomed) win.putSetting("welcomed", true)
    }
    Sheet {
        id: aboutSheet
        title: "Sheaf"
        message: "Version " + Qt.application.version + "\nScan documents and photos: USB and network scanners (SANE), searchable PDFs (tesseract)."
        GLabel { width: parent.width; text: "github.com/benwbooth/sheaf"; color: Theme.fgSecondary }
        buttons: [ PushButton { primary: true; text: "OK"; onClicked: aboutSheet.close() } ]
    }
    Sheet {
        id: closeSheet
        title: "Save the scanned pages before closing?"
        message: pages.count + (pages.count === 1 ? " page hasn't" : " pages haven't") + " been saved. If you don't save, they're lost."
        buttons: [
            PushButton { text: "Don't Save"; destructive: true; tip: "Close and lose the pages"; onClicked: { win.reallyClose = true; closeSheet.close(); win.close() } },
            PushButton { text: "Cancel"; tip: "Keep the window open"; onClicked: closeSheet.close() },
            PushButton { primary: true; text: "Save…"; onClicked: { closeSheet.close(); win.afterSaveQuit = true; saveSheet.open() } }
        ]
    }
    Sheet {
        id: startOverSheet
        title: "Remove every page?"
        message: "The " + pages.count + " scanned " + (pages.count === 1 ? "page goes" : "pages go") + " away (Undo brings them back)."
        buttons: [
            PushButton { text: "Cancel"; onClicked: startOverSheet.close() },
            PushButton {
                primary: true
                text: "Remove All"
                onClicked: {
                    const all = []
                    for (let i = 0; i < pages.count; i++) all.push(i)
                    win.deletePages(all)
                    win.dirty = false
                    startOverSheet.close()
                }
            }
        ]
    }

    // ---- test hook: SHEAF_TEST steps, then --screenshot ----
    readonly property string testSpec: sheaf.env("SHEAF_TEST")
    readonly property string shotPath: sheaf.env("SHEAF_SCREENSHOT")
    readonly property bool testing: testSpec !== "" || shotPath !== ""
    property var testSteps: testSpec ? testSpec.split(";").filter(s => s) : []
    property int testWait: 0
    Timer {
        id: testTimer
        interval: 250
        repeat: true
        onTriggered: {
            if (win.testWait > 0) { win.testWait--; return }
            if (sheaf.busy || sheaf.opening || sheaf.searching || win.pageWorking || saveSheet.saving) return
            if (!win.testSteps.length) {
                stop()
                if (win.shotPath) sheaf.grabWindows(win.shotPath)
                Qt.quit()
                return
            }
            const s = win.testSteps.shift()
            const [cmd, arg] = [s.split("=")[0], s.split("=").slice(1).join("=")]
            console.log("sheaf test:", s)
            win.testWait = 2
            switch (cmd) {
            case "device": sheaf.openDevice(arg); break
            case "set": { const [n, v] = arg.split(":"); sheaf.setOption(n, isNaN(Number(v)) ? JSON.stringify(v) : v); break }
            case "preview": win.doPreview(); break
            case "select": win.area = arg.split(",").map(Number); break
            case "detect": win.act("detect"); break
            case "scan": win.doScan(); break
            case "page": win.openPage(Number(arg)); break
            case "view": win.view = Number(arg); break
            case "act": win.act(arg); break
            case "wait": win.testWait = Number(arg || 4); break
            case "shot": sheaf.grabWindows(win.shotPath.replace(".png", "-" + arg + ".png")); break
            case "save": {
                const [folder, format, ocr] = arg.split(",")
                win.doSave({ name: "Test", folder: folder, format: format || "pdf", ocr: ocr === "ocr", quality: 85, onlySelected: false })
                saveSheet.saving = true
                break
            }
            case "sheet": { const m = { save: saveSheet, options: optionsSheet, settings: settingsSheet, help: helpWindow, welcome: welcome }; m[arg].open(); break }
            }
        }
    }

    // Resizing from the edges (no system frame).
    ChromeResizeEdges { anchors.fill: parent; z: 10000; window: win }
}
