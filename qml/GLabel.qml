import QtQuick

// All text in sheaf: native rendering, the system face at 13 pt.
Text {
    color: Theme.fg
    font.family: Theme.family
    font.pixelSize: Theme.body
    renderType: Text.NativeRendering
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
    textFormat: Text.PlainText
}
