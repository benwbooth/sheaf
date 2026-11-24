import QtQuick

// Three pulsing dots (working on it).
Row {
    id: d
    property bool running: true
    property color color: Theme.fgSecondary
    visible: running
    spacing: 5
    Repeater {
        model: 3
        Rectangle {
            required property int index
            width: 6; height: 6; radius: 3
            color: d.color
            opacity: 0.3
            SequentialAnimation on opacity {
                running: d.running
                loops: Animation.Infinite
                PauseAnimation { duration: index * 160 }
                NumberAnimation { to: 1; duration: 320 }
                NumberAnimation { to: 0.3; duration: 320 }
                PauseAnimation { duration: (2 - index) * 160 }
            }
        }
    }
}
