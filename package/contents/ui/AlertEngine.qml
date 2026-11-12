import QtQuick

// Alertas do sistema: avisa uma vez quando a bateria fica baixa, o disco enche, a CPU esquenta ou a internet
// cai. Cada alerta só volta a disparar depois que o valor se recupera (com folga), para não repetir aviso.
// As leituras vêm de fora (main.qml); aqui só há a decisão, por isso dá para testar com `fakeNow`.
Item {
    id: engine
    property bool enabled: true
    // Limites (0 desliga o alerta correspondente).
    property int batteryLow: 20       // % de bateria
    property int diskFull: 90         // % do disco usado
    property int tempHigh: 85         // °C da CPU
    property int offlineSeconds: 45   // internet fora por tanto tempo antes de avisar (0 desliga)
    // Leituras atuais (-1 = sem dado).
    property real battery: -1
    property bool charging: false
    property real disk: -1
    property real temp: -1
    property bool online: true
    property real fakeNow: 0          // só os testes usam
    signal notify(string title, string body, string key)
    // Silenciar um alerta por um tempo (o botão "Silenciar 1 h" da notificação). Passado o prazo, se o problema
    // continuar, ele avisa de novo.
    property var mutedUntil: ({})
    function mute(key, ms) { const next = Object.assign({}, mutedUntil); next[key] = nowMs() + ms; mutedUntil = next }
    function isMuted(key) { return (mutedUntil[key] || 0) > nowMs() }

    function nowMs() { return fakeNow > 0 ? fakeNow : Date.now() }
    // Alertas já disparados e ainda não recuperados: low, disk, temp, net.
    property var fired: ({})
    property real offlineSince: 0

    function fire(key, title, body) {
        if (fired[key] || isMuted(key)) return
        const next = Object.assign({}, fired); next[key] = true; fired = next
        notify(title, body, key)
    }
    function clear(key) {
        if (!fired[key]) return false
        const next = Object.assign({}, fired); delete next[key]; fired = next
        return true
    }

    function check() {
        if (!enabled) return
        const now = nowMs()
        // Bateria: só conta descarregando; ligar na tomada ou subir 5 pontos rearma.
        if (batteryLow > 0 && battery >= 0) {
            if (!charging && battery <= batteryLow) fire("low", "Bateria baixa", Math.round(battery) + "% restantes. Conecte o carregador.")
            else if (charging || battery > batteryLow + 5) clear("low")
        }
        if (diskFull > 0 && disk >= 0) {
            if (disk >= diskFull) fire("disk", "Disco quase cheio", Math.round(disk) + "% do armazenamento em uso.")
            else if (disk < diskFull - 3) clear("disk")
        }
        if (tempHigh > 0 && temp > 0) {
            if (temp >= tempHigh) fire("temp", "CPU muito quente", Math.round(temp) + " °C. Verifique a ventilação e os processos pesados.")
            else if (temp < tempHigh - 5) clear("temp")
        }
        if (offlineSeconds > 0) {
            if (online) {
                offlineSince = 0
                if (clear("net")) notify("Internet de volta", "A conexão foi restabelecida.", "net-back")
            } else {
                if (offlineSince <= 0) offlineSince = now
                else if (now - offlineSince >= offlineSeconds * 1000) fire("net", "Sem internet", "A conexão caiu há mais de " + offlineSeconds + " s.")
            }
        }
    }
    Timer { interval: 15000; repeat: true; running: engine.enabled; triggeredOnStart: true; onTriggered: engine.check() }
}
