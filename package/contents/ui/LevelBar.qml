import QtQuick

// Barra de nível que se arrasta ou se toca (volume, brilho…). value vai de 0 a 1.
Item {
    id: bar
    required property var t
    property real value: 0
    property color color: t.accent
    property bool dimmed: false
    signal moved(real value)
    signal released()
    implicitHeight: 18
    opacity: dimmed ? 0.45 : 1

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: area.containsMouse || area.pressed ? 6 : 4; radius: 3; color: bar.t.border
        Behavior on height { NumberAnimation { duration: 100 } }
        Rectangle { width: parent.width * Math.max(0, Math.min(1, bar.value)); height: parent.height; radius: 3; color: bar.color }
    }
    Rectangle {   // pegador
        visible: area.containsMouse || area.pressed
        width: 12; height: 12; radius: 6; color: bar.t.ink
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(1, bar.value)) * (parent.width - width)
    }
    MouseArea {
        id: area
        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        function emit(mouseX) { bar.moved(Math.max(0, Math.min(1, mouseX / width))) }
        onPressed: mouse => emit(mouse.x)
        onPositionChanged: mouse => { if (pressed) emit(mouse.x) }
        onReleased: bar.released()
    }
}
