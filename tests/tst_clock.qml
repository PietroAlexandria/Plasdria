import QtQuick
import QtTest
import "../package/contents/ui"

// Motor do cronômetro, do timer e do pomodoro, com relógio de mentira (fakeNow): nada depende de esperar.
Item {
    id: root
    width: 400; height: 400
    property var notices: []
    property string saved: ""
    readonly property real start: new Date(2026, 5, 10, 8, 0, 0).getTime()

    ClockEngine {
        id: engine
        fakeNow: root.start             // um instante fixo: 8h da manhã, longe da virada do dia
        onNotify: (title, body) => root.notices.push(title + ": " + body)
        onPersist: json => root.saved = json
    }
    Theme { id: theme }
    ClockCard { id: card; t: theme; clock: engine; width: 380 }

    TestCase {
        name: "RelogioEPomodoro"
        when: windowShown

        function init() {
            engine.fakeNow = root.start
            engine.swReset(); engine.tmReset(); engine.pomReset()
            engine.pomToday = 0; engine.pomDay = ""
            engine.tmTotal = 600000; engine.tab = "stopwatch"
            engine.focusMin = 25; engine.shortMin = 5; engine.longMin = 15
            root.notices = []
        }

        function test_cronometro_corre_pausa_e_marca_voltas() {
            engine.swToggle()
            engine.fakeNow += 12300
            compare(Math.round(engine.swElapsed()), 12300)
            engine.swLap()
            engine.fakeNow += 4100
            engine.swLap()
            compare(engine.laps.map(l => [l.n, l.total, l.split]), [[2, 16400, 4100], [1, 12300, 12300]])
            engine.swToggle()                      // pausa
            engine.fakeNow += 99999
            compare(Math.round(engine.swElapsed()), 16400)   // parado não corre
            engine.swToggle()
            engine.fakeNow += 600
            compare(Math.round(engine.swElapsed()), 17000)
            engine.swReset()
            compare(engine.swElapsed(), 0)
            compare(engine.laps.length, 0)
        }

        function test_timer_conta_pausa_e_avisa_ao_acabar() {
            engine.tmSet(5)
            compare(engine.tmRemaining(), 300000)
            engine.tmToggle()
            verify(engine.tmRunning)
            engine.fakeNow += 120000
            compare(Math.round(engine.tmRemaining()), 180000)
            engine.tmToggle()                      // pausa
            engine.fakeNow += 500000
            compare(Math.round(engine.tmRemaining()), 180000)
            verify(engine.tmPaused)
            engine.tmSet(1)                        // não troca a duração no meio
            compare(engine.tmTotal, 300000)
            engine.tmToggle()                      // continua
            engine.fakeNow += 180000
            engine.checkExpiry()
            compare(root.notices, ["Timer: O tempo acabou!"])
            verify(!engine.tmRunning && !engine.tmPaused)
            compare(engine.tmRemaining(), 300000)  // volta à duração escolhida
            engine.checkExpiry()
            compare(root.notices.length, 1, "avisa uma vez só")
        }

        function test_pomodoro_quatro_focos_e_pausa_longa() {
            engine.pomToggle()
            const esperado = ["short", "focus", "short", "focus", "short", "focus", "long", "focus"]
            for (let i = 0; i < esperado.length; ++i) {
                const duracao = engine.pomPhase === "focus" ? 25 : engine.pomPhase === "short" ? 5 : 15
                engine.fakeNow += duracao * 60000
                engine.checkExpiry()
                compare(engine.pomPhase, esperado[i], "etapa " + (i + 1))
                verify(engine.pomRunning, "segue correndo sozinho")
            }
            compare(engine.pomToday, 4)
            compare(engine.pomCycle, 0, "o ciclo recomeça depois da pausa longa")
            verify(root.notices[0].indexOf("Pomodoro concluído: Hora da pausa curta (5 min)") === 0)
            verify(root.notices[6].indexOf("Hora da pausa longa (15 min)") > 0, "7ª notificação: " + root.notices[6])
            verify(root.notices[7].indexOf("Pausa terminada") === 0, "8ª notificação: " + root.notices[7])
        }

        function test_pomodoro_pular_nao_conta_e_zerar() {
            engine.pomToggle()
            engine.pomSkip()                       // pula o foco sem concluir
            compare(engine.pomPhase, "short")
            compare(engine.pomToday, 0)
            engine.pomSkip()
            compare(engine.pomPhase, "focus")
            engine.pomReset()
            verify(!engine.pomRunning)
            compare(engine.pomCycle, 0)
        }

        function test_pomodoro_respeita_duracoes_configuradas() {
            engine.focusMin = 50; engine.shortMin = 10
            compare(engine.pomRemaining(), 50 * 60000)
            engine.pomToggle()
            engine.fakeNow += 50 * 60000
            engine.checkExpiry()
            compare(engine.pomRemaining(), 10 * 60000)
        }

        function test_estado_sobrevive_ao_reiniciar() {
            engine.swToggle(); engine.fakeNow += 5000; engine.swLap()
            engine.tmSet(10); engine.tmToggle()
            engine.pomToggle(); engine.fakeNow += 60000
            const json = root.saved
            verify(json.length > 20)
            const novo = Qt.createQmlObject('import "../package/contents/ui"; ClockEngine {}', root)
            novo.fakeNow = engine.fakeNow
            novo.load(json)
            compare(novo.swRunning, true)
            compare(Math.round(novo.swElapsed()), Math.round(engine.swElapsed()))
            compare(novo.laps.length, 1)
            compare(Math.round(novo.tmRemaining()), Math.round(engine.tmRemaining()))
            compare(Math.round(novo.pomRemaining()), Math.round(engine.pomRemaining()))
            novo.destroy()
        }

        function test_o_que_venceu_com_o_widget_fechado_encerra_em_silencio() {
            engine.tmSet(5); engine.tmToggle()
            engine.pomToggle()
            const json = root.saved
            const novo = Qt.createQmlObject('import "../package/contents/ui"; ClockEngine {}', root)
            novo.fakeNow = engine.fakeNow + 3 * 3600000     // 3 h depois
            novo.load(json)
            verify(!novo.tmRunning && !novo.tmPaused)
            verify(!novo.pomRunning)
            novo.destroy()
            compare(root.notices.length, 0, "sem avisos atrasados")
            // JSON estragado ou de outra versão é ignorado.
            const outro = Qt.createQmlObject('import "../package/contents/ui"; ClockEngine {}', root)
            outro.load("isto nao e json"); outro.load('{"v":99}')
            compare(outro.swRunning, false)
            outro.destroy()
        }

        function test_formato_do_tempo_no_cartao() {
            compare(card.fmt(83400, false), "01:23")
            compare(card.fmt(83400, true), "01:23.4")
            compare(card.fmt(3723000, false), "1:02:03")
            compare(card.fmt(-5, false), "00:00")
        }
    }
}
