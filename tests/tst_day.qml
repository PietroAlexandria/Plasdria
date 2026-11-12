import QtQuick
import QtTest
import "../package/contents/ui"

// Cartão "Resumo do dia" com agenda, lembretes e clima de mentira.
Item {
    id: root
    width: 400; height: 600
    Theme { id: theme }
    readonly property real now: new Date(2026, 10, 11, 10, 0).getTime()
    QtObject {
        id: dash
        property string weatherLocation: "Ourinhos"
        property string weatherTemperature: "22°C"
        property string weatherSummary: "Encoberto · Ameno"
        property var weatherDetails: ({high: 29, low: 18, rainChance: 84, uv: 3})
    }
    DayCard {
        id: card
        t: theme; dash: dash; width: 380
        nowMs: root.now
        events: [{title: "Treino", start: new Date(2026, 10, 11, 18, 0).getTime(), end: new Date(2026, 10, 11, 19, 0).getTime(), allDay: false, location: ""}]
        stored: JSON.stringify([{text: "Entregar trabalho", due: new Date(2026, 10, 11, 9, 0).getTime(), done: false}])
        aiReady: true
    }
    SignalSpy { id: spy; target: card; signalName: "askAi" }
    TestCase {
        name: "CartaoDoDia"
        when: windowShown
        readonly property string good: JSON.stringify([{text: "Entregar trabalho", due: new Date(2026, 10, 11, 9, 0).getTime(), done: false}])
        function init() { card.stored = good; spy.clear() }
        function test_monta_as_tres_secoes() {
            const s = card.summary
            compare(s.sections.map(x => x.kind), ["agenda", "reminders", "weather"])
            compare(s.sections[0].lines, ["18:00  Treino"])
            compare(s.sections[1].lines, ["Atrasado  Entregar trabalho"])
            compare(s.sections[2].lines[0], "Ourinhos · 22°C · Encoberto")
            verify(s.sections[2].lines.indexOf("Leve guarda-chuva.") >= 0)
        }
        function test_botao_da_ia_envia_o_texto_do_resumo() {
            card.askAi(card.summary.text)
            compare(spy.count, 1)
            verify(spy.signalArguments[0][0].indexOf("Agenda de hoje:") === 0)
        }
        function test_lembretes_estragados_nao_quebram() {
            card.stored = "isso nao e json"
            compare(card.summary.sections[1].lines.length, 0)
            card.stored = '{"nao":"lista"}'
            compare(card.summary.sections[1].lines.length, 0)
        }
    }
}
