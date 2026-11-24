import QtQuick

// A liquid-glass pane (hearth's GlassFrame look, drawn in-window): tint,
// a sheen at the top, a bright rim lit from the top-left and a hairline
// outline. arbor's real glass only exists for shell layers, so windows
// draw their own.
Item {
    id: g
    property color tint: Theme.glass
    property real radius: Theme.glassRadius
    property bool shadow: true

    Rectangle {
        visible: g.shadow
        anchors.fill: parent
        anchors.topMargin: 3
        anchors.margins: -1
        radius: g.radius + 1
        color: "transparent"
        border.width: 3
        border.color: Qt.rgba(0, 0, 0, Theme.dark ? 0.22 : 0.06)
    }
    Rectangle {
        anchors.fill: parent
        radius: g.radius
        color: g.tint
        border.width: 1
        border.color: Theme.glassEdge
    }
    // Sheen in the top part.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: g.radius - 1
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, Theme.dark ? 0.05 : 0.25) }
            GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0) }
        }
    }
    // Specular rim (top-left light).
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: g.radius - 1
        color: "transparent"
        border.width: 1
        border.color: Theme.glassRim
        opacity: 0.9
    }
}
