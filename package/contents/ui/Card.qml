import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Cartão com título, ícone e uma área de ações opcional à direita.
Rectangle {
    id: card
    required property var t
    property string title
    property string icon
    property alias actions: actionRow.data
    default property alias content: body.data
    property int padding: t.pad
    // true: o conteúdo ocupa a altura toda (listas, gráficos). false: fica no topo.
    property bool stretch: false

    radius: t.radius
    color: t.card
    border.color: t.border
    implicitHeight: column.implicitHeight + padding * 2
    Layout.fillWidth: true

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: card.padding
        spacing: 8
        RowLayout {
            visible: card.title !== ""
            Layout.fillWidth: true
            spacing: 7
            Kirigami.Icon { visible: card.icon !== ""; source: card.icon; implicitWidth: Math.round(15 * card.t.iconScale); implicitHeight: implicitWidth; color: card.t.accent; isMask: true }
            Text { text: card.title; color: card.t.muted; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.8; font.capitalization: Font.AllUppercase; Layout.fillWidth: true; elide: Text.ElideRight }
            Row { id: actionRow; spacing: 2 }
        }
        ColumnLayout { id: body; Layout.fillWidth: true; Layout.fillHeight: card.stretch; spacing: 8 }
        Item { visible: !card.stretch; Layout.fillHeight: true }
    }
}
