import QtQuick

// Medidor circular (0–100) com rótulo no centro.
Item {
    id: ring
    property real value: -1
    property color color: "#8b7cff"
    property color track: "#2c2f3d"
    property real thickness: 5
    property string label: value < 0 ? "—" : Math.round(value) + "%"
    property string caption
    property color ink: "#eceef5"
    property color mutedInk: "#9ba1b5"
    property int duration: 400
    implicitWidth: 58; implicitHeight: 58 + (caption ? 16 : 0)

    property real shown: Math.max(0, value)
    Behavior on shown { NumberAnimation { duration: ring.duration; easing.type: Easing.OutCubic } }
    onShownChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()
    onTrackChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        width: Math.min(ring.width, ring.height - (ring.caption ? 16 : 0)); height: width
        anchors.horizontalCenter: parent.horizontalCenter
        onPaint: {
            const ctx = getContext("2d"); ctx.reset()
            const r = width / 2 - ring.thickness / 2, c = width / 2
            ctx.lineWidth = ring.thickness; ctx.lineCap = "round"
            ctx.strokeStyle = ring.track; ctx.beginPath(); ctx.arc(c, c, r, 0, Math.PI * 2); ctx.stroke()
            if (ring.shown > 0) {
                ctx.strokeStyle = ring.color; ctx.beginPath()
                ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.min(ring.shown, 100) / 100); ctx.stroke()
            }
        }
        Text { anchors.centerIn: parent; text: ring.label; color: ring.ink; font.pixelSize: Math.max(10, parent.width * 0.22); font.weight: Font.DemiBold }
    }
    Text {
        visible: ring.caption !== ""
        anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
        text: ring.caption; color: ring.mutedInk; font.pixelSize: 10
    }
}
