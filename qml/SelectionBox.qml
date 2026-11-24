import QtQuick

// A box drawn over a picture: drag on the picture to draw it, drag inside
// to move it, drag its corners or edges to resize. `area` is [x0, y0, x1,
// y1] in fractions of the picture, or null (no box). Fill the picture's
// painted rectangle with this item.
Item {
    id: sb
    property var area: null
    property bool editable: true
    property color color: Theme.accent
    signal edited(var area)

    readonly property real minSize: 12
    function clamp01(v) { return Math.max(0, Math.min(1, v)) }
    function setArea(a) {
        if (!a) { area = null; edited(null); return }
        const x0 = clamp01(Math.min(a[0], a[2])), x1 = clamp01(Math.max(a[0], a[2]))
        const y0 = clamp01(Math.min(a[1], a[3])), y1 = clamp01(Math.max(a[1], a[3]))
        area = [x0, y0, x1, y1]
        edited(area)
    }

    // Dim what's outside the box.
    Rectangle { visible: sb.area !== null; color: Qt.rgba(0, 0, 0, 0.35); x: 0; y: 0; width: parent.width; height: box.y }
    Rectangle { visible: sb.area !== null; color: Qt.rgba(0, 0, 0, 0.35); x: 0; y: box.y + box.height; width: parent.width; height: parent.height - y }
    Rectangle { visible: sb.area !== null; color: Qt.rgba(0, 0, 0, 0.35); x: 0; y: box.y; width: box.x; height: box.height }
    Rectangle { visible: sb.area !== null; color: Qt.rgba(0, 0, 0, 0.35); x: box.x + box.width; y: box.y; width: parent.width - x; height: box.height }

    // Drawing a new box.
    MouseArea {
        anchors.fill: parent
        enabled: sb.editable
        cursorShape: Qt.CrossCursor
        property real sx: 0
        property real sy: 0
        onPressed: m => { sx = m.x; sy = m.y }
        onPositionChanged: m => {
            if (Math.abs(m.x - sx) < 4 && Math.abs(m.y - sy) < 4) return
            sb.setArea([sx / sb.width, sy / sb.height, m.x / sb.width, m.y / sb.height])
        }
    }

    Rectangle {
        id: box
        visible: sb.area !== null
        x: sb.area ? sb.area[0] * sb.width : 0
        y: sb.area ? sb.area[1] * sb.height : 0
        width: sb.area ? (sb.area[2] - sb.area[0]) * sb.width : 0
        height: sb.area ? (sb.area[3] - sb.area[1]) * sb.height : 0
        color: "transparent"
        border.color: sb.color
        border.width: 2

        // Moving the box.
        MouseArea {
            anchors.fill: parent
            anchors.margins: 8
            enabled: sb.editable
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property real px: 0
            property real py: 0
            property var start: null
            onPressed: m => { const p = mapToItem(sb, m.x, m.y); px = p.x; py = p.y; start = sb.area.slice() }
            onPositionChanged: m => {
                if (!start) return
                const p = mapToItem(sb, m.x, m.y)
                let dx = (p.x - px) / sb.width, dy = (p.y - py) / sb.height
                dx = Math.max(-start[0], Math.min(1 - start[2], dx))
                dy = Math.max(-start[1], Math.min(1 - start[3], dy))
                sb.setArea([start[0] + dx, start[1] + dy, start[2] + dx, start[3] + dy])
            }
            onReleased: start = null
        }

        GLabel {
            visible: box.width > 90 && box.height > 30
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: 6
            text: "Drag to move"
            font.pixelSize: Theme.caption
            color: "white"
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.6)
        }
    }

    // Resize handles: [fx, fy] says which edges each one moves.
    Repeater {
        model: [[0, 0], [0.5, 0], [1, 0], [1, 0.5], [1, 1], [0.5, 1], [0, 1], [0, 0.5]]
        delegate: Rectangle {
            id: h
            required property var modelData
            visible: sb.area !== null && sb.editable
            width: 12; height: 12; radius: 6
            color: "white"
            border.color: sb.color
            border.width: 2
            x: box.x + modelData[0] * box.width - width / 2
            y: box.y + modelData[1] * box.height - height / 2
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: (h.modelData[0] === 0.5) ? Qt.SizeVerCursor : (h.modelData[1] === 0.5) ? Qt.SizeHorCursor
                    : (h.modelData[0] === h.modelData[1]) ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                onPositionChanged: m => {
                    const p = mapToItem(sb, m.x, m.y)
                    const a = sb.area.slice()
                    const fx = p.x / sb.width, fy = p.y / sb.height
                    if (h.modelData[0] === 0) a[0] = Math.min(fx, a[2] - sb.minSize / sb.width)
                    if (h.modelData[0] === 1) a[2] = Math.max(fx, a[0] + sb.minSize / sb.width)
                    if (h.modelData[1] === 0) a[1] = Math.min(fy, a[3] - sb.minSize / sb.height)
                    if (h.modelData[1] === 1) a[3] = Math.max(fy, a[1] + sb.minSize / sb.height)
                    sb.setArea(a)
                }
            }
        }
    }
}
