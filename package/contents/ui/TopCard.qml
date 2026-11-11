import QtQuick
import QtQuick.Layouts

// Programas que mais usam processador e memória (somando os processos de cada programa).
Card {
    id: card
    required property var sys
    title: "Maiores consumidores"
    icon: "office-chart-bar-percentage-symbolic"
    property string tab: "cpu"

    // Só mede enquanto o cartão está na tela.
    Component.onCompleted: sys.acquireTop()
    Component.onDestruction: sys.releaseTop()

    function memoryText(bytes) {
        const gb = bytes / 1073741824
        return gb >= 1 ? gb.toFixed(1).replace(".", ",") + " GB" : Math.round(bytes / 1048576) + " MB"
    }
    readonly property var rows: tab === "cpu" ? sys.topCpu : sys.topMemory
    readonly property real peak: {
        let m = 0.0001
        for (const r of rows) m = Math.max(m, tab === "cpu" ? r.cpu : r.memory)
        return m
    }

    actions: [
        Row {
            spacing: 4
            Repeater {
                model: [{id: "cpu", name: "CPU"}, {id: "memory", name: "Memória"}]
                delegate: Rectangle {
                    required property var modelData
                    height: 20; width: tabText.implicitWidth + 16; radius: 10
                    color: card.tab === modelData.id ? card.t.accentSoft : "transparent"
                    border.color: card.tab === modelData.id ? card.t.accentLine : card.t.border
                    Text { id: tabText; anchors.centerIn: parent; text: modelData.name; color: card.tab === modelData.id ? card.t.accent : card.t.muted; font.pixelSize: 10; font.weight: Font.DemiBold }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: card.tab = modelData.id }
                }
            }
        }
    ]

    Text { visible: card.rows.length === 0; text: "Medindo…"; color: card.t.faint; font.pixelSize: 12 }
    Repeater {
        model: card.rows
        delegate: ColumnLayout {
            required property var modelData
            Layout.fillWidth: true; spacing: 2
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Text { text: modelData.name; color: card.t.ink; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
                Text { visible: modelData.count > 1; text: "×" + modelData.count; color: card.t.faint; font.pixelSize: 10 }
                Text {
                    text: card.tab === "cpu" ? modelData.cpu.toFixed(1).replace(".", ",") + "%" : card.memoryText(modelData.memory)
                    color: card.t.muted; font.pixelSize: 11; Layout.preferredWidth: 54; horizontalAlignment: Text.AlignRight
                }
            }
            Rectangle {
                Layout.fillWidth: true; height: 4; radius: 2; color: card.t.border
                Rectangle {
                    height: parent.height; radius: 2
                    width: parent.width * Math.max(0.02, (card.tab === "cpu" ? modelData.cpu : modelData.memory) / card.peak)
                    color: card.tab === "cpu" ? card.t.usageColor(modelData.cpu * 3) : card.t.accent
                    Behavior on width { NumberAnimation { duration: card.t.duration } }
                }
            }
        }
    }
}
