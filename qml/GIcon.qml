import QtQuick

// A theme icon by freedesktop name ("document-save", "a|fallback").
// tint recolours one-colour glyphs (toolbar buttons). Drawn at exactly
// the device pixels it's shown at: shrinking line art loses thin strokes.
Image {
    property string name: ""
    property int size: 16
    property color tint: "transparent"
    width: size
    height: size
    sourceSize.width: size
    sourceSize.height: size
    source: name ? Theme.iconUrl(name, tint) : ""
    asynchronous: true
    smooth: true
    cache: true
}
