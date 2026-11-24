pragma Singleton
import QtQuick

// Colours, type and sizes: macOS 26 ("Tahoe") Finder, matched to hearth's
// Look spec (hearth README): 1 pt = 1.125 logical px, SF Pro or Inter at
// 13 pt, 12 pt glass corners, accent selection. Follows hearth's light/dark
// mode and accent when its settings exist, else sheaf's own setting.
QtObject {
    id: t

    // Set by Main.qml from sheaf's settings and hearth's appearance.
    property string mode: "auto"          // auto, dark, light
    property var hearth: ({})
    // hearth's Reduce motion: no gliding or extra animation.
    readonly property bool reduceMotion: (hearth || {}).reduceMotion === true
    // Toolbar glyph: the "-symbolic" form of each name first (one-colour
    // glyphs as in Finder's toolbar), then the names as given.
    function glyph(name) {
        if (!name) return ""
        const ns = name.split("|")
        return ns.map(n => n.endsWith("-symbolic") ? n : n + "-symbolic").concat(ns).join("|")
    }
    function iconUrl(name, tint) {
        if (!name) return ""
        const t = tint !== undefined && tint.a > 0 ? "&tint=" + tint.toString().replace("#", "") : ""
        return "image://icon/" + name + "?r=" + (dark ? "d" : "l") + t
    }
    readonly property bool hearthDark: {
        const m = (hearth || {}).mode || "dark"
        if (m === "light") return false
        if (m === "auto") { const h = new Date().getHours(); return h < 7 || h >= 19 }
        return true
    }
    readonly property bool dark: mode === "dark" ? true : mode === "light" ? false : hearthDark

    readonly property real pt: 1.125

    // --- colours ---
    readonly property color accent: (hearth || {}).accent || (dark ? "#0a84ff" : "#007aff")
    readonly property color accentText: "#ffffff"
    readonly property color window: dark ? "#1e1e20" : "#ffffff"
    readonly property color content: dark ? "#1e1e20" : "#ffffff"
    readonly property color sidebar: dark ? Qt.rgba(0.20, 0.205, 0.22, 0.97) : Qt.rgba(0.955, 0.955, 0.965, 0.98)
    readonly property color toolbar: window
    readonly property color glass: dark ? Qt.rgba(0.24, 0.245, 0.26, 0.92) : Qt.rgba(0.985, 0.985, 0.99, 0.94)
    readonly property color glassMenu: dark ? Qt.rgba(0.17, 0.175, 0.19, 0.995) : Qt.rgba(0.975, 0.975, 0.98, 0.995)
    readonly property color glassRim: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.85)
    readonly property color glassEdge: dark ? Qt.rgba(0, 0, 0, 0.6) : Qt.rgba(0, 0, 0, 0.13)
    readonly property color fg: dark ? "#f5f5f7" : "#1d1d1f"
    readonly property color fgSecondary: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.5)
    readonly property color fgTertiary: dark ? Qt.rgba(1, 1, 1, 0.32) : Qt.rgba(0, 0, 0, 0.28)
    readonly property color fgDisabled: dark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0, 0, 0, 0.26)
    readonly property color separator: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.09)
    readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.05)
    readonly property color pressed: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10)
    readonly property color selectedInactive: dark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(0, 0, 0, 0.08)
    readonly property color rowAlt: dark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(0, 0, 0, 0.028)
    readonly property color field: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
    readonly property color danger: "#ff453a"
    readonly property color good: "#30d158"
    readonly property color shadow: Qt.rgba(0, 0, 0, dark ? 0.45 : 0.18)
    readonly property color dropTarget: Qt.rgba(accent.r, accent.g, accent.b, 0.25)

    // --- type ---
    readonly property var families: Qt.fontFamilies()
    function has(f) { return families.indexOf(f) >= 0 }
    readonly property string family: has("SF Pro") ? "SF Pro" : has("SF Pro Text") ? "SF Pro Text"
        : has("Inter") ? "Inter" : has("Inter Variable") ? "Inter Variable" : has("Noto Sans") ? "Noto Sans" : "sans-serif"
    // Inter is ~4% larger than SF at the same size.
    readonly property real fontScale: family.indexOf("Inter") === 0 ? 0.962 : 1.0
    readonly property real body: Math.round(13 * pt * fontScale * 10) / 10       // 13 pt
    readonly property real small: Math.round(11 * pt * fontScale * 10) / 10      // 11 pt
    readonly property real caption: Math.round(10 * pt * fontScale * 10) / 10
    readonly property real title: Math.round(15 * pt * fontScale * 10) / 10
    readonly property real large: Math.round(20 * pt * fontScale * 10) / 10
    readonly property string mono: has("JetBrains Mono") ? "JetBrains Mono" : has("SF Mono") ? "SF Mono" : "monospace"

    // --- metrics ---
    readonly property int toolbarHeight: Math.round(52 * pt)
    readonly property int controlHeight: Math.round(28 * pt)
    readonly property int rowHeight: Math.round(24 * pt)
    readonly property int sidebarRow: Math.round(26 * pt)
    readonly property int radius: Math.round(6 * pt)
    readonly property int glassRadius: Math.round(12 * pt)
    readonly property int windowRadius: Math.round(16 * pt)
    readonly property int menuRow: Math.round(24 * pt)
    readonly property int menuPad: Math.round(5 * pt)
    readonly property int spacing: 8
    readonly property int tooltipDelay: 800

    // --- motion ---
    readonly property int fast: 120
    readonly property int normal: 180
}
