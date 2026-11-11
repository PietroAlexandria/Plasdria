import QtQuick
import QtQuick.Shapes

Item {
    id: root
    required property var t
    property int code: 0
    property bool animated: true
    readonly property bool sunny: code >= 0 && code <= 2
    readonly property bool cloudy: code > 0
    readonly property bool rain: (code >= 51 && code <= 67) || (code >= 80 && code <= 82) || code >= 95
    readonly property bool snow: (code >= 71 && code <= 77) || code === 85 || code === 86
    implicitWidth: 42; implicitHeight: 42
    Item {
        id: sun; objectName: "weatherSun"
        visible: root.sunny; x: root.cloudy ? 1 : 8; y: 3
        width: 26; height: 26
        Repeater {
            model: 8
            delegate: Item {
                required property int index
                anchors.fill: parent; rotation: index * 45
                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 0; width: 2; height: 4; radius: 1; color: root.t.sunRay }
            }
        }
        Rectangle { anchors.centerIn: parent; width: 15; height: 15; radius: 8; color: root.t.sunCore }
        RotationAnimator on rotation { from: 0; to: 360; duration: 28000; loops: Animation.Infinite; running: root.animated && root.visible && root.sunny }
    }
    Item {
        id: cloud; objectName: "weatherCloud"
        visible: root.cloudy; x: 6; y: 5; width: 34; height: 20
        Rectangle { x: 2; y: 8; width: 31; height: 12; radius: 6; color: root.t.cloudA }
        Rectangle { x: 7; y: 3; width: 15; height: 15; radius: 8; color: root.t.cloudB }
        Rectangle { x: 17; y: 6; width: 13; height: 13; radius: 7; color: root.t.cloudA }
        SequentialAnimation on x {
            running: root.animated && root.visible && root.cloudy; loops: Animation.Infinite
            NumberAnimation { from: 5; to: 8; duration: 2200; easing.type: Easing.InOutSine }
            NumberAnimation { from: 8; to: 5; duration: 2200; easing.type: Easing.InOutSine }
        }
    }
    Repeater {
        model: root.rain || root.snow ? (root.code >= 95 ? 2 : 3) : 0
        delegate: Rectangle {
            required property int index
            x: root.code >= 95 ? cloud.x + 2 + index * 26 : 11 + index * 9; y: 26
            width: root.snow ? 3 : 2; height: root.snow ? 3 : 5; radius: 1.5; color: root.t.rainDrop; rotation: root.snow ? 0 : 15
            SequentialAnimation on y {
                running: root.animated && root.visible; loops: Animation.Infinite
                PauseAnimation { duration: index * 170 }
                NumberAnimation { from: 26; to: 35; duration: 700; easing.type: Easing.InQuad }
                PauseAnimation { duration: 200 }
            }
            SequentialAnimation on opacity { running: root.animated && root.visible; loops: Animation.Infinite; NumberAnimation { from: .25; to: 1; duration: 550 } NumberAnimation { from: 1; to: .25; duration: 550 } }
        }
    }
    Shape {
        objectName: "weatherLightning"
        visible: root.code >= 95
        x: cloud.x + (cloud.width - width) / 2; y: cloud.y + 13
        width: 12; height: 20; opacity: .85
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 0; strokeColor: "transparent"; fillColor: root.t.sunCore
            PathSvg { path: "M6 0H10L7 7H12L3 20L5 11H0Z" }
        }
        SequentialAnimation on opacity {
            running: root.animated && root.visible && root.code >= 95; loops: Animation.Infinite
            PauseAnimation { duration: 1300 }
            NumberAnimation { from: .65; to: 1; duration: 90 }
            NumberAnimation { from: 1; to: .35; duration: 80 }
            NumberAnimation { from: .35; to: 1; duration: 100 }
            NumberAnimation { from: 1; to: .65; duration: 260 }
        }
    }
}
