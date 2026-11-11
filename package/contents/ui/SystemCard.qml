import QtQuick
import QtQuick.Layouts

// Uso de CPU, GPU, RAM e disco em anéis, com detalhes do hardware embaixo.
Card {
    id: card
    required property var dash
    property var sys: null
    // O anel de GPU precisa da leitura enquanto o cartão está na tela.
    Component.onCompleted: if (sys) sys.acquire("gpu")
    Component.onDestruction: if (sys) sys.release("gpu")
    title: "Sistema"
    icon: "computer-symbolic"
    readonly property var d: dash.systemDetails || ({})
    function gib(used, total) { return used < 0 || total <= 0 ? "—" : used.toFixed(1) + " / " + Math.round(total) + " GiB" }
    function temp(v) { return v > 0 ? Math.round(v) + "°C" : "—" }

    GridLayout {
        columns: 4; columnSpacing: 4; rowSpacing: 0
        Layout.fillWidth: true
        Repeater {
            model: [
                {name: "CPU", value: card.dash.cpuUsage},
                {name: "GPU", value: card.sys && card.sys.gpuUsage >= 0 ? card.sys.gpuUsage : card.dash.gpuUsage},
                {name: "RAM", value: card.dash.memoryUsage},
                {name: "Disco", value: card.dash.storageUsage}
            ]
            delegate: Ring {
                required property var modelData
                Layout.fillWidth: true; Layout.preferredHeight: 54
                value: modelData.value; caption: modelData.name
                color: card.t.usageColor(modelData.value); track: card.t.border
                ink: card.t.ink; mutedInk: card.t.muted; duration: card.t.animations ? 500 : 0
                thickness: 4.5
            }
        }
    }
    Rectangle { Layout.fillWidth: true; height: 1; color: card.t.border }
    GridLayout {
        Layout.fillWidth: true
        columns: 2; columnSpacing: 10; rowSpacing: 4
        Repeater {
            model: [
                ["Processador", (card.d.cpuModel || "—") + (card.d.cores ? " · " + card.d.cores + " threads" : "")],
                ["Temperatura", "CPU " + card.temp(card.d.cpuTemp) + "  ·  SSD " + card.temp(card.d.diskTemp)],
                ["Memória", card.gib(card.dash.memoryUsedGiB, card.dash.memoryTotalGiB) + (card.d.swapTotalGiB > 0 ? "  ·  swap " + card.d.swapUsedGiB.toFixed(1) + " GiB" : "")],
                ["Disco", card.gib(card.dash.storageUsedGiB, card.dash.storageTotalGiB)],
                ["Carga", (card.d.load || "—") + (card.d.processes ? "  ·  " + card.d.processes + " processos" : "")],
                ["Sistema", [card.d.distro, card.d.kernel ? "kernel " + card.d.kernel : ""].filter(Boolean).join(" · ") || "—"]
            ]
            delegate: Repeater {
                required property var modelData
                model: 2
                delegate: Text {
                    required property int index
                    text: modelData[index]
                    color: index === 0 ? card.t.faint : card.t.ink
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.fillWidth: index === 1
                    Layout.preferredWidth: index === 0 ? 72 : -1
                }
            }
        }
    }
}
