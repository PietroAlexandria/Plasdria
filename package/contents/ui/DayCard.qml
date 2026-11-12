import QtQuick
import QtQuick.Layouts
import "timeparse.js" as TP

// Resumo do dia: agenda, lembretes e clima num só lugar. Montado aqui mesmo, sem IA; o botão pede à IA
// do chat uma versão comentada.
Card {
    id: card
    required property var dash
    property var events: []
    property string stored: "[]"        // lembretes (JSON)
    property bool aiReady: false
    property real nowMs: Date.now()     // atualiza a cada minuto
    signal askAi(string text)
    title: "Resumo do dia"
    icon: "view-calendar-day"

    Timer { interval: 60000; repeat: true; running: card.visible; onTriggered: card.nowMs = Date.now() }

    readonly property var summary: {
        let list = []
        try { list = JSON.parse(stored) } catch (e) {}
        const w = dash.weatherDetails || ({})
        return TP.daySummary({
            now: nowMs, events: events, reminders: Array.isArray(list) ? list : [],
            weather: {place: dash.weatherLocation, temp: dash.weatherTemperature, summary: (dash.weatherSummary || "").split(" · ")[0],
                      high: w.high === undefined ? -1000 : w.high, low: w.low === undefined ? -1000 : w.low,
                      rain: w.rainChance === undefined ? -1 : w.rainChance, uv: w.uv === undefined ? -1 : w.uv}})
    }
    readonly property var kindIcons: ({agenda: "view-calendar", reminders: "task-reminder", weather: "weather-clear"})

    Repeater {
        model: card.summary.sections
        delegate: ColumnLayout {
            required property var modelData
            Layout.fillWidth: true; spacing: 3
            Text { text: modelData.title; color: card.t.accent; font.pixelSize: 11; font.weight: Font.DemiBold }
            Repeater {
                model: modelData.lines
                delegate: Text { required property string modelData; text: modelData; color: card.t.ink; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }
            Text { visible: modelData.lines.length === 0; text: modelData.empty; color: card.t.faint; font.pixelSize: 12; Layout.fillWidth: true }
        }
    }
    Rectangle {
        Layout.preferredHeight: 28; Layout.preferredWidth: aiText.implicitWidth + 28; radius: 14
        enabled: card.aiReady; opacity: enabled ? 1 : 0.5
        color: aiHover.hovered ? card.t.accentSoft : "transparent"; border.color: card.t.accentLine
        Text { id: aiText; anchors.centerIn: parent; text: "Resumir com a IA"; color: card.t.accent; font.pixelSize: 12; font.weight: Font.DemiBold }
        HoverHandler { id: aiHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: card.askAi(card.summary.text) }
    }
}
