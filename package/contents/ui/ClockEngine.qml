import QtQuick

// Motor do cronômetro, do timer e do pomodoro. Vive no main.qml (e não no cartão) para que os alarmes
// toquem mesmo com o cartão oculto e para que o estado sobreviva ao recriar o cartão ou reiniciar o Plasma:
// tudo é guardado como instantes absolutos (ms desde a época), nunca como "tempo restante" correndo.
Item {
    id: engine
    // Duração do pomodoro, em minutos (vem das configurações).
    property int focusMin: 25
    property int shortMin: 5
    property int longMin: 15
    property string tab: "stopwatch"  // aba do cartão (só em memória): stopwatch | timer | pomodoro
    property real fakeNow: 0          // só os testes usam: relógio de mentira
    property real tick: 0             // muda a cada 100 ms enquanto algo roda: as telas atualizam por ele
    signal notify(string title, string body)
    signal persist(string json)

    function nowMs() { return fakeNow > 0 ? fakeNow : Date.now() }
    function dayKey(ms) { const d = new Date(ms); return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate() }

    // ── Cronômetro ──
    property real swStart: 0          // instante em que começou a correr (0 = parado)
    property real swAccum: 0          // ms acumulados antes da última pausa
    property var laps: []             // [{n, total, split}] em ms, da mais nova para a mais antiga
    readonly property bool swRunning: swStart > 0
    function swElapsed() { tick; return swAccum + (swStart > 0 ? nowMs() - swStart : 0) }
    function swToggle() {
        if (swStart > 0) { swAccum += nowMs() - swStart; swStart = 0 } else swStart = nowMs()
        save()
    }
    function swLap() {
        if (swStart <= 0) return
        const total = swElapsed(), last = laps.length ? laps[0].total : 0
        laps = [{n: laps.length + 1, total: total, split: total - last}].concat(laps).slice(0, 50)
        save()
    }
    function swReset() { swStart = 0; swAccum = 0; laps = []; save() }

    // ── Timer ──
    property real tmEnd: 0            // instante em que acaba (0 = não está correndo)
    property real tmLeft: 0           // ms que faltavam quando foi pausado
    property real tmTotal: 600000     // duração escolhida
    readonly property bool tmRunning: tmEnd > 0
    readonly property bool tmPaused: tmEnd <= 0 && tmLeft > 0
    function tmRemaining() { tick; return tmEnd > 0 ? Math.max(0, tmEnd - nowMs()) : (tmLeft > 0 ? tmLeft : tmTotal) }
    function tmSet(minutes) { if (tmEnd > 0 || tmLeft > 0) return; tmTotal = Math.max(1, Math.min(600, minutes)) * 60000; save() }
    function tmToggle() {
        if (tmEnd > 0) { tmLeft = Math.max(1, tmEnd - nowMs()); tmEnd = 0 }
        else { tmEnd = nowMs() + (tmLeft > 0 ? tmLeft : tmTotal); tmLeft = 0 }
        save()
    }
    function tmReset() { tmEnd = 0; tmLeft = 0; save() }

    // ── Pomodoro ──
    property string pomPhase: "focus"   // focus | short | long
    property real pomEnd: 0
    property real pomLeft: 0
    property int pomCycle: 0            // focos concluídos desde a última pausa longa (0..4)
    property int pomToday: 0
    property string pomDay: ""
    readonly property bool pomRunning: pomEnd > 0
    function pomTotal(phase) { return (phase === "focus" ? focusMin : phase === "short" ? shortMin : longMin) * 60000 }
    function pomRemaining() { tick; return pomEnd > 0 ? Math.max(0, pomEnd - nowMs()) : (pomLeft > 0 ? pomLeft : pomTotal(pomPhase)) }
    function pomToggle() {
        if (pomEnd > 0) { pomLeft = Math.max(1, pomEnd - nowMs()); pomEnd = 0 }
        else { pomEnd = nowMs() + (pomLeft > 0 ? pomLeft : pomTotal(pomPhase)); pomLeft = 0 }
        save()
    }
    function pomReset() { pomEnd = 0; pomLeft = 0; pomPhase = "focus"; pomCycle = 0; save() }
    function pomSkip() { advance(false, pomEnd > 0) }
    // Passa para a próxima etapa; `completed` conta o foco; `running` mantém o relógio correndo.
    function advance(completed, running) {
        const today = dayKey(nowMs())
        if (pomDay !== today) { pomDay = today; pomToday = 0 }
        if (pomPhase === "focus") {
            if (completed) { pomCycle++; pomToday++ }
            pomPhase = completed && pomCycle >= 4 ? "long" : "short"
        } else {
            if (pomPhase === "long") pomCycle = 0
            pomPhase = "focus"
        }
        pomLeft = 0
        pomEnd = running ? nowMs() + pomTotal(pomPhase) : 0
        save()
    }

    readonly property bool anyRunning: swStart > 0 || tmEnd > 0 || pomEnd > 0
    Timer {
        interval: 100; repeat: true; running: engine.anyRunning
        onTriggered: { engine.tick++; engine.checkExpiry() }
    }
    function checkExpiry() {
        const now = nowMs()
        if (tmEnd > 0 && now >= tmEnd) {
            tmEnd = 0; tmLeft = 0
            notify("Timer", "O tempo acabou!")
            save()
        }
        if (pomEnd > 0 && now >= pomEnd) {
            const wasFocus = pomPhase === "focus"
            advance(wasFocus, true)
            notify(wasFocus ? "Pomodoro concluído" : "Pausa terminada",
                   wasFocus ? "Hora da pausa " + (pomPhase === "long" ? "longa" : "curta") + " (" + Math.round(pomTotal(pomPhase) / 60000) + " min)."
                            : "De volta ao foco por " + Math.round(pomTotal("focus") / 60000) + " min.")
        }
    }

    // ── Persistência ──
    function save() { persist(JSON.stringify({v: 1, sw: {start: swStart, accum: swAccum, laps: laps}, tm: {end: tmEnd, left: tmLeft, total: tmTotal},
                                              pom: {phase: pomPhase, end: pomEnd, left: pomLeft, cycle: pomCycle, today: pomToday, day: pomDay}})) }
    // Restaura o estado. O que venceu enquanto o widget estava fechado é encerrado em silêncio (sem avisos antigos).
    function load(text) {
        let s
        try { s = JSON.parse(text) } catch (e) { return }
        if (!s || s.v !== 1) return
        const now = nowMs()
        swStart = s.sw.start > 0 && s.sw.start <= now ? s.sw.start : 0
        swAccum = s.sw.accum > 0 ? s.sw.accum : 0
        laps = Array.isArray(s.sw.laps) ? s.sw.laps : []
        tmTotal = s.tm.total > 0 ? s.tm.total : 600000
        tmEnd = s.tm.end > now ? s.tm.end : 0
        tmLeft = s.tm.end > 0 && s.tm.end <= now ? 0 : (s.tm.left > 0 ? s.tm.left : 0)
        const phases = ["focus", "short", "long"]
        pomPhase = phases.indexOf(s.pom.phase) >= 0 ? s.pom.phase : "focus"
        pomCycle = s.pom.cycle >= 0 && s.pom.cycle <= 4 ? s.pom.cycle : 0
        pomDay = s.pom.day || ""
        pomToday = pomDay === dayKey(now) && s.pom.today > 0 ? s.pom.today : 0
        pomEnd = s.pom.end > now ? s.pom.end : 0
        pomLeft = s.pom.end > 0 && s.pom.end <= now ? 0 : (s.pom.left > 0 ? s.pom.left : 0)
    }
}
