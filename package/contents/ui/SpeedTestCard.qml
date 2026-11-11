import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "timeparse.js" as TP

// Teste de velocidade da internet: latência, download e upload (servidores da Cloudflare).
// Só roda quando você toca em "Iniciar" e consome dados (algo entre 50 e 300 MB em conexão rápida).
Card {
    id: card
    required property var speed
    title: "Teste de velocidade"
    icon: "speedometer-symbolic"

    property real now: Date.now()
    Timer { interval: 30000; running: true; repeat: true; onTriggered: card.now = Date.now() }

    function mbps(v) { return v < 0 ? "—" : (v >= 100 ? Math.round(v) : v.toFixed(1)).toString().replace(".", ",") }
    function ms(v) { return v < 0 ? "—" : (v >= 10 ? Math.round(v) : v.toFixed(1)).toString().replace(".", ",") + " ms" }
    readonly property bool hasResult: speed.downloadMbps >= 0 && !speed.running
    readonly property var last: speed.history.length > 0 ? speed.history[0] : null
    readonly property string phaseText: speed.phase === "ping" ? "Medindo a latência…" : speed.phase === "download" ? "Medindo o download…" : speed.phase === "upload" ? "Medindo o upload…" : ""

    component Button: Rectangle {
        id: button
        property string text
        property bool solid: true
        signal clicked()
        Layout.preferredHeight: 30; Layout.preferredWidth: label.implicitWidth + 30; radius: 15
        color: solid ? (hover.hovered ? Qt.lighter(card.t.accent, 1.1) : card.t.accent) : (hover.hovered ? card.t.cardRaised : "transparent")
        border.color: solid ? "transparent" : card.t.border
        Text { id: label; anchors.centerIn: parent; text: button.text; font.pixelSize: 12; font.weight: Font.DemiBold; color: button.solid ? card.t.textOnAccent : card.t.muted }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: button.clicked() }
    }

    // Em andamento
    ColumnLayout {
        visible: card.speed.running
        Layout.fillWidth: true; spacing: 6
        RowLayout {
            Layout.fillWidth: true
            Text { text: card.phaseText; color: card.t.muted; font.pixelSize: 12; Layout.fillWidth: true }
            Button { text: "Cancelar"; solid: false; onClicked: card.speed.cancel() }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: 6; visible: card.speed.phase !== "ping"
            Kirigami.Icon { source: card.speed.phase === "download" ? "go-down-symbolic" : "go-up-symbolic"; implicitWidth: 22; implicitHeight: 22; isMask: true; color: card.t.accent }
            Text { text: card.mbps(card.speed.liveMbps); color: card.t.ink; font.pixelSize: 40; font.weight: Font.Light }
            Text { text: "Mb/s"; color: card.t.faint; font.pixelSize: 13; Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: 9 }
        }
        Rectangle {
            Layout.fillWidth: true; height: 4; radius: 2; color: card.t.border
            Rectangle { width: parent.width * card.speed.progress; height: parent.height; radius: 2; color: card.t.accent }
        }
        Text { visible: card.speed.pingMs >= 0; text: "Latência " + card.ms(card.speed.pingMs) + " · " + card.speed.server; color: card.t.faint; font.pixelSize: 10 }
    }

    // Resultado do último teste
    ColumnLayout {
        visible: !card.speed.running && card.hasResult
        Layout.fillWidth: true; spacing: 8
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Repeater {
                model: [{icon: "go-down-symbolic", name: "Download", value: card.speed.downloadMbps}, {icon: "go-up-symbolic", name: "Upload", value: card.speed.uploadMbps}]
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 70; radius: 10
                    color: card.t.tint; border.color: card.t.border
                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 0
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter; spacing: 4
                            Kirigami.Icon { source: modelData.icon; implicitWidth: 14; implicitHeight: 14; isMask: true; color: card.t.accent }
                            Text { text: modelData.name; color: card.t.muted; font.pixelSize: 11 }
                        }
                        Text { text: card.mbps(modelData.value); color: card.t.ink; font.pixelSize: 26; font.weight: Font.Light; Layout.alignment: Qt.AlignHCenter }
                        Text { text: "Mb/s"; color: card.t.faint; font.pixelSize: 10; Layout.alignment: Qt.AlignHCenter }
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 14
            Text { text: "Latência  " + card.ms(card.speed.pingMs); color: card.t.muted; font.pixelSize: 11 }
            Text { text: "Jitter  " + card.ms(card.speed.jitterMs); color: card.t.muted; font.pixelSize: 11 }
            Item { Layout.fillWidth: true }
            Text { text: card.speed.server; color: card.t.faint; font.pixelSize: 10; elide: Text.ElideRight }
        }
    }

    // Antes do primeiro teste ou depois de erro
    Text {
        visible: !card.speed.running && !card.hasResult && card.speed.error === ""
        text: card.last ? "Último teste " + TP.formatDue(card.last.time * 1000, card.now) + ": ↓ " + card.mbps(card.last.down) + " ↑ " + card.mbps(card.last.up) + " Mb/s" : "Mede a latência, o download e o upload da sua conexão."
        color: card.t.faint; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
    }
    Text { visible: card.speed.error !== ""; text: card.speed.error; color: card.t.warn; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }

    RowLayout {
        visible: !card.speed.running
        Layout.fillWidth: true; spacing: 8
        Button { text: card.hasResult || card.last ? "Testar de novo" : "Iniciar teste"; onClicked: card.speed.start() }
        Text { text: "Usa de 50 a 300 MB de dados"; color: card.t.faint; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
    }

    // Histórico
    Sparkline {
        visible: card.speed.history.length > 2
        Layout.fillWidth: true; Layout.preferredHeight: 34
        values: card.speed.history.map(h => h.down).reverse(); color: card.t.accent
    }
    Repeater {
        model: card.speed.history.slice(0, 3)
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true; spacing: 8
            Text { text: TP.formatDue(modelData.time * 1000, card.now); color: card.t.faint; font.pixelSize: 10; Layout.preferredWidth: 78 }
            Text { text: "↓ " + card.mbps(modelData.down) + "  ↑ " + card.mbps(modelData.up) + " Mb/s"; color: card.t.muted; font.pixelSize: 11; Layout.fillWidth: true }
            Text { text: card.ms(modelData.ping); color: card.t.faint; font.pixelSize: 10 }
        }
    }
}
