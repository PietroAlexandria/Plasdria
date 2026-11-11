import QtQuick
import QtQuick.Controls.Basic as B
import org.kde.kirigami as Kirigami

// Botão redondo só com ícone, com dica ao passar o mouse.
Rectangle {
    id: button
    required property var t
    property string icon
    property string tip
    property int size: 26
    property bool active: false
    property bool primary: false
    property bool colored: false   // mostra o ícone com as cores originais (ex.: logo do Spotify)
    signal clicked()

    width: size; height: size; radius: size / 2
    color: primary ? t.accent : active ? t.accentSoft : hover.hovered ? t.cardRaised : "transparent"
    opacity: enabled ? 1 : 0.35
    Behavior on color { ColorAnimation { duration: button.t.duration } }
    Kirigami.Icon {
        anchors.centerIn: parent
        source: button.icon
        width: Math.round(button.size * 0.58); height: width
        isMask: !button.colored
        color: button.primary ? button.t.textOnAccent : button.active ? button.t.accent : button.t.ink
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: button.clicked() }
    B.ToolTip.visible: hover.hovered && tip !== ""
    B.ToolTip.text: tip
    B.ToolTip.delay: 500
    Accessible.role: Accessible.Button
    Accessible.name: tip
}
