pragma Singleton
import QtQuick

// Every action with its shortcut (for menus, tooltips and the Shortcuts
// page) and the help topics (the searchable Help window). Ctrl stands
// where a Mac has ⌘.
QtObject {
    readonly property var shortcuts: [
        { id: "overview", group: "Scanning", action: "Overview (a quick look at what's on the glass)", keys: ["Ctrl+Shift+P"] },
        { id: "scan", group: "Scanning", action: "Scan", keys: ["Ctrl+Return"] },
        { id: "stop", group: "Scanning", action: "Stop scanning", keys: ["Esc"] },
        { id: "wholearea", group: "Scanning", action: "Scan the whole glass (clear the selection)", keys: ["Ctrl+Shift+A"] },
        { id: "detect", group: "Scanning", action: "Select the document found on the overview", keys: ["Ctrl+D"] },
        { id: "moreoptions", group: "Scanning", action: "More scanner options", keys: ["Ctrl+Shift+O"] },
        { id: "refresh", group: "Scanning", action: "Look for scanners again", keys: ["F5"] },

        { id: "rotleft", group: "Pages", action: "Rotate left", keys: ["Ctrl+L"] },
        { id: "rotright", group: "Pages", action: "Rotate right", keys: ["Ctrl+R"] },
        { id: "straighten", group: "Pages", action: "Straighten (fix a tilted page)", keys: ["Ctrl+T"] },
        { id: "autocrop", group: "Pages", action: "Crop to the content", keys: ["Ctrl+K"] },
        { id: "crop", group: "Pages", action: "Crop by hand (drag a box, then Crop)", keys: ["Ctrl+Shift+K"] },
        { id: "moveup", group: "Pages", action: "Move page earlier", keys: ["Ctrl+Left"] },
        { id: "movedown", group: "Pages", action: "Move page later", keys: ["Ctrl+Right"] },
        { id: "delete", group: "Pages", action: "Delete the selected pages", keys: ["Delete", "Backspace"] },
        { id: "selectall", group: "Pages", action: "Select all pages", keys: ["Ctrl+A"] },
        { id: "openpage", group: "Pages", action: "Look at a page up close", keys: ["Return"] },
        { id: "prevpage", group: "Pages", action: "Previous / next page", keys: ["Left", "Right"] },
        { id: "backtoscanner", group: "Pages", action: "Back to the scanner", keys: ["Ctrl+1"] },
        { id: "pagesview", group: "Pages", action: "Show the selected page", keys: ["Ctrl+2"] },
        { id: "undo", group: "Pages", action: "Undo", keys: ["Ctrl+Z"] },

        { id: "save", group: "File", action: "Save…", keys: ["Ctrl+S"] },
        { id: "startover", group: "File", action: "Start over (remove every page)", keys: ["Ctrl+Shift+N"] },
        { id: "settings", group: "File", action: "Settings", keys: ["Ctrl+,"] },
        { id: "sidebar", group: "File", action: "Show or hide the scanner list", keys: ["Ctrl+Alt+S"] },
        { id: "close", group: "File", action: "Close the window", keys: ["Ctrl+W"] },
        { id: "quit", group: "File", action: "Quit", keys: ["Ctrl+Q"] },

        { id: "help", group: "Help", action: "Sheaf Help", keys: ["F1"] },
        { id: "shortcutlist", group: "Help", action: "Keyboard shortcuts", keys: ["Ctrl+/"] }
    ]

    function entry(id) {
        for (const s of shortcuts) if (s.id === id) return s
        return null
    }
    // The first shortcut of an action ("" none), for menus.
    function key(id) {
        const e = entry(id)
        return e && e.keys.length ? e.keys[0] : ""
    }
    // "Rotate left (Ctrl+L)" for tooltips.
    function tip(text, id) {
        const k = key(id)
        return k ? text + "  (" + k + ")" : text
    }

    readonly property var topics: [
        { title: "Scanning a page", body: "1. Pick your scanner in the list on the left.\n2. Put the page face down on the glass and click Overview: a quick, rough scan shows what's there.\n3. Drag a box over the part you want (or leave it, to scan the whole glass).\n4. Choose the kind of picture and the resolution on the right, then click Scan.\nThe page appears in the tray at the bottom. Scan more pages the same way; they all go into one document when you save." },
        { title: "Scanning many pages with the document feeder", body: "If your scanner has a document feeder (ADF), choose it under Source on the right, put the pages in the feeder and click Scan. Sheaf scans every page until the feeder is empty.\nTo scan both sides of each sheet, choose the source that says Duplex, or turn on Both Sides when your scanner has it.\nAn overview can't be made from the feeder: it needs the flatbed." },
        { title: "Choosing a resolution", body: "Resolution is how many dots per inch (dpi) are scanned.\n• 150 dpi: fine for reading on screen and emailing.\n• 300 dpi: the usual choice for documents and for text recognition.\n• 600 dpi or more: photos you want to enlarge or print, small print.\nHigher resolutions take longer and make bigger files." },
        { title: "Kind of picture (colour, gray, text)", body: "Colour keeps colours (photos, forms with coloured stamps).\nGray is black and white with shades in between: good for most letters and receipts, and smaller than colour.\nText (line art) is pure black and white: the smallest files, crisp text, but photos turn into dots." },
        { title: "Selecting part of the glass", body: "On the overview, drag to draw a box around what you want. Drag inside the box to move it, or drag its corners and edges to change its size.\nDetect Document draws the box around the document sheaf found on the overview.\nWhole Glass removes the box, so the whole glass is scanned.\nThe Size menu on the right has common paper sizes (A4, Letter…)." },
        { title: "Fixing pages: rotate, straighten, crop", body: "Hover over a page in the tray for quick rotate and delete buttons, or select it and use the Page menu.\nStraighten turns a page that was put on the glass a little crooked so its lines of text are level.\nCrop to Content trims the empty border around what's on the page.\nCrop by Hand: open the page (double-click it), click Crop, drag a box and click Crop again.\nSheaf can straighten and crop every new page by itself: see Straighten and Crop on the right.\nEvery change can be undone with Undo (Ctrl+Z)." },
        { title: "Putting pages in order", body: "Drag a page in the tray to where it should go, or select it and press Ctrl+Left / Ctrl+Right.\nTo delete pages, select them (Ctrl-click or Shift-click selects several) and press Delete." },
        { title: "Saving", body: "Click Save… (Ctrl+S). Give the file a name, choose a folder and a format:\n• PDF: every page in one document. Turn on Searchable Text to recognise the words on the pages, so you can search and copy them.\n• PNG: a picture file per page, without any loss of quality.\n• JPEG: a smaller picture file per page (good for photos).\nAfter saving, sheaf shows the file in Grove (you can change this in Settings)." },
        { title: "Searchable text (OCR)", body: "When you save a PDF with Searchable Text, sheaf reads the words on each page (text recognition, with tesseract) and puts them invisibly over the picture. You can then search the PDF, select and copy its text.\nIt works best at 300 dpi in gray or colour. The language to read is in Settings." },
        { title: "My scanner isn't in the list", body: "• Make sure it's turned on and finished starting up.\n• USB scanners: check the cable; try another port.\n• Network scanners: the computer and the scanner must be on the same network. Most scanners from the last ten years work through AirScan (eSCL).\n• Click ↻ (or press F5) to look again; network scanners can take a few seconds to answer.\n• Some older scanners need a driver from their maker (a SANE backend) installed on the system." },
        { title: "The scanner is busy or doesn't answer", body: "Only one app can use a scanner at a time: close other scanning apps. If a scan stopped half way, turn the scanner off and on, then pick it again in the list." },
        { title: "More scanner options", body: "Scanner > More Options shows everything your scanner can be set to (brightness, contrast, sharpness, colour correction…). Which ones there are depends on the scanner. Hover over an option to see what it does. Sheaf remembers your choices for each scanner." }
    ]
}
