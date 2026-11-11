import QtQuick
import QtQuick.Layouts

// Placa de vídeo: uso, histórico, frequência, temperatura e memória (o que o driver informar).
Card {
    id: card
    required property var sys
    required property var dash   // NVIDIA continua sendo lida pelo painel (nvidia-smi)
    title: "GPU"
    icon: "monitor-symbolic"

    readonly property real usage: sys.gpuUsage >= 0 ? sys.gpuUsage : dash.gpuUsage
    readonly property bool known: sys.gpuName !== "" || usage >= 0
    readonly property var details: {
        const rows = []
        if (sys.gpuFrequency >= 0) rows.push(["Frequência", Math.round(sys.gpuFrequency) + (sys.gpuFrequencyMax > 0 ? " / " + Math.round(sys.gpuFrequencyMax) : "") + " MHz"])
        if (sys.gpuTemperature >= 0) rows.push(["Temperatura", Math.round(sys.gpuTemperature) + "°C"])
        if (sys.gpuMemoryTotal > 0) rows.push(["Memória", (sys.gpuMemoryUsed / 1073741824).toFixed(1).replace(".", ",") + " / " + (sys.gpuMemoryTotal / 1073741824).toFixed(1).replace(".", ",") + " GB"])
        if (sys.gpuDriver) rows.push(["Driver", sys.gpuDriver])
        return rows
    }

    Text { visible: !card.known; text: "Nenhuma placa de vídeo encontrada."; color: card.t.faint; font.pixelSize: 12 }
    RowLayout {
        visible: card.known
        Layout.fillWidth: true; spacing: 12
        Ring {
            value: card.usage; color: card.t.usageColor(card.usage); track: card.t.border
            ink: card.t.ink; mutedInk: card.t.muted; duration: card.t.duration
            Layout.preferredWidth: 58; Layout.preferredHeight: 58
        }
        ColumnLayout {
            spacing: 1; Layout.fillWidth: true
            Text { text: card.sys.gpuName || "GPU"; color: card.t.ink; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
            Text { text: card.usage >= 0 ? "Em uso: " + Math.round(card.usage) + "%" : "Uso não informado pelo driver"; color: card.t.muted; font.pixelSize: 11 }
        }
    }
    Sparkline {
        visible: card.known && card.sys.gpuHistory.length > 2
        Layout.fillWidth: true; Layout.preferredHeight: 38
        values: card.sys.gpuHistory; color: card.t.accent
    }
    GridLayout {
        visible: card.known && card.details.length > 0
        Layout.fillWidth: true; columns: 2; columnSpacing: 12; rowSpacing: 2
        Repeater {
            model: card.details
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true; spacing: 6
                Text { text: modelData[0]; color: card.t.faint; font.pixelSize: 11; Layout.preferredWidth: 70 }
                Text { text: modelData[1]; color: card.t.ink; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
            }
        }
    }
}
