import QtQuick
import QtQuick.Window
import "../package/contents/ui"
import "../package/contents/ui/bridge" as Backend

// Captura telas do widget fora do Plasma, com dados reais:
//   qml6 tools/preview.qml -- <pasta-de-saída> ["pergunta ao Claude (usa Haiku)"] [--sem-rede] [--editar] [--novos] [--demo] [--claro]
// --sem-rede oculta o cartão de rede (nome do Wi-Fi e IP) para capturas públicas.
Window {
    id: win
    width: 1300; height: 820; visible: true; color: "#0b0c10"
    readonly property var args: { const a = Qt.application.arguments; const i = a.indexOf("--"); return i >= 0 ? a.slice(i + 1) : [] }
    readonly property var positional: args.filter(a => !a.startsWith("--"))
    readonly property string outDir: positional[0] || "."
    readonly property string question: positional[1] || ""
    readonly property bool hideNetwork: args.indexOf("--sem-rede") >= 0
    readonly property bool edit: args.indexOf("--editar") >= 0
    readonly property bool demo: args.indexOf("--demo") >= 0
    readonly property bool welcome: args.indexOf("--boasvindas") >= 0
    readonly property string tabName: { const a = args.filter(x => x.startsWith("--aba=")); return a.length ? a[0].slice(6) : "" }
    readonly property bool novos: args.indexOf("--novos") >= 0   // mostra os cartões novos (áudio, Bluetooth, consumidores, GPU, atalhos)
    QtObject {
        id: cfg
        property string userName: "Pietro"
        property bool showAudio: true; property bool showBluetooth: true; property bool showTop: true; property bool showGpu: true; property bool showShortcuts: true; property bool showSpeedTest: true; property bool showClock: true
        property string layout: win.novos ? JSON.stringify({cols: [{w: 0.95, c: ["system", "gpu", "top"]}, {w: 1.2, c: ["chat"]}, {w: 1, c: ["media", "clock", "speedtest", "shortcuts"]}, {w: 1, c: ["reminders", "calendar", "news"]}], hidden: ["devices", "network"]}) : ""
        property string shortcuts: "[]"
        property int welcomeSeen: win.welcome ? 0 : 1
        property bool showWeather: true; property bool showSystem: true; property bool showConnections: true
        property bool showCalendar: true
        property bool showMedia: true; property bool showNetwork: !win.hideNetwork; property bool showReminders: true; property bool showNews: true
        property string reminders: win.demo ? JSON.stringify([{id: "a", text: "Entregar trabalho de cálculo", done: false, due: Date.now() + 5 * 3600000, notified: false}, {id: "c", text: "Ligar para o João", done: false, due: Date.now() - 1800000, notified: true}, {id: "b", text: "Comprar café", done: true}]) : '[{"id":"a","text":"Entregar trabalho de cálculo","done":false},{"id":"b","text":"Comprar café","done":true}]'
    }
    Theme { id: theme; mode: win.args.indexOf("--claro") >= 0 ? "light" : "dark" }
    Backend.ClaudeClient { id: client; Component.onCompleted: start() }
    Backend.DashboardClient { id: dash; Component.onCompleted: { setLocation("Ourinhos", -22.97889, -49.87056); start() } }
    Backend.MediaClient { id: media }
    Backend.SystemClient { id: systemBackend }
    Backend.SpeedTestClient { id: speedBackend }
    ClockEngine { id: clockBackend }
    Backend.NetworkClient { id: realNet }
    // Com --sem-rede, o nome do Wi-Fi não aparece nas capturas públicas.
    QtObject {
        id: maskedNet
        readonly property bool online: realNet.online
        readonly property int latency: realNet.latency
        readonly property string connectionName: "Wi-Fi"
        readonly property real downloadRate: realNet.downloadRate
        function formatRate(v) { return realNet.formatRate(v) }
    }
    readonly property var netSource: win.hideNetwork ? maskedNet : realNet
    Shell { id: shell; editing: win.edit;
        feedConfigured: win.demo
        events: win.demo ? win.demoEvents : []; anchors.fill: parent; anchors.margins: 10; t: theme; client: client; dash: dash; media: media; net: win.netSource; cfg: cfg; sys: systemBackend; speed: speedBackend; clock: clockBackend }

    // Eventos de exemplo (para as capturas do README).
    readonly property var demoEvents: {
        const d = new Date(), at = (days, h, m) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + days, h, m).getTime()
        return [
            {title: "Aula de Cálculo II", start: at(0, 19, 0), end: at(0, 22, 30), allDay: false, location: "Sala 12"},
            {title: "Treino", start: at(0, 7, 0), end: at(0, 8, 0), allDay: false, location: ""},
            {title: "Reunião do projeto", start: at(1, 14, 0), end: at(1, 15, 0), allDay: false, location: ""},
            {title: "Prova de Física", start: at(3, 8, 0), end: at(3, 10, 0), allDay: false, location: ""},
            {title: "Aniversário da Ana", start: at(6, 0, 0), end: at(7, 0, 0), allDay: true, location: ""}]
    }
    // Atalhos de exemplo com aplicativos que existem de verdade neste computador.
    Timer { interval: 1500; running: win.novos; onTriggered: {
        const wanted = ["Firefox", "Dolphin", "Konsole", "Spotify", "Blender", "Antigravity"], apps = systemBackend.applications(), picked = []
        for (const w of wanted) { const a = apps.find(x => x.name.indexOf(w) === 0); if (a) picked.push({name: a.name, target: "app:" + a.id, icon: a.icon}) }
        picked.push({name: "github.com", target: "https://github.com/PietroAlexandria/Plasdria", icon: "internet-web-browser"})
        cfg.shortcuts = JSON.stringify(picked.slice(0, 6)) } }
    Timer { interval: 1200; running: win.tabName !== ""; onTriggered: {
        clockBackend.tab = win.tabName
        if (win.tabName === "stopwatch") { clockBackend.swToggle(); clockBackend.swStart -= 83400; clockBackend.laps = [{n: 2, total: 83400, split: 31200}, {n: 1, total: 52200, split: 52200}] }
        if (win.tabName === "timer") { clockBackend.tmSet(25); clockBackend.tmToggle(); clockBackend.tmEnd -= 9 * 60000 }
        if (win.tabName === "pomodoro") { clockBackend.pomCycle = 2; clockBackend.pomToday = 3; clockBackend.pomToggle(); clockBackend.pomEnd -= 7 * 60000 + 20000 } } }
    property int stage: 0
    function shot(name, next) { win.contentItem.grabToImage(r => { r.saveToFile(outDir + "/" + name + ".png"); console.log("SHOT", name); next() }) }
    Timer {
        interval: 9000; running: true
        onTriggered: {
            if (win.question && client.ready) { client.model = "haiku"; client.effort = "low"; client.send(win.question); waitReply.start() }
            else win.shots()
        }
    }
    Timer { id: waitReply; interval: 500; repeat: true; onTriggered: if (!client.busy) { stop(); win.shots() } }
    // --tamanhos=LxA,LxA,...  (padrão: largo, médio e estreito)
    readonly property var sizes: {
        const a = win.args.filter(x => x.startsWith("--tamanhos="))
        const list = a.length ? a[0].slice(11).split(",") : ["1300x820", "980x820", "430x760"]
        return list.map(x => x.split("x").map(Number))
    }
    property int sizeIndex: 0
    function shots() { applySize() }
    function applySize() {
        if (sizeIndex >= sizes.length) { Qt.quit(); return }
        win.width = sizes[sizeIndex][0]; win.height = sizes[sizeIndex][1]
        delay.start()
    }
    Timer { id: delay; interval: 900; onTriggered: {
        const name = sizes.length === 3 && !win.args.some(x => x.startsWith("--tamanhos=")) ? ["wide", "medium", "narrow"][win.sizeIndex] : win.width + "x" + win.height
        win.shot(name, () => { win.sizeIndex++; win.applySize() }) } }
}
