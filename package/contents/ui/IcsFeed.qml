import QtQuick
import "timeparse.js" as TP

// Lê agendas iCalendar (links .ics, como o "endereço secreto em formato iCal" do Google Agenda)
// e mantém a lista de eventos dos próximos dois meses. Atualiza a cada 15 minutos.
// Sem internet, continua mostrando o que já foi baixado.
Item {
    id: feed
    // Um link por linha (webcal:// também vale).
    property string urls: ""
    property var events: []
    property var errors: ({})      // link -> mensagem do último erro (some quando o link volta a funcionar)
    readonly property string status: { for (const u of list) if (errors[u]) return errors[u]; return "" }
    readonly property var list: urls.split(/\s+/).map(u => u.trim().replace(/^webcal:/i, "https:")).filter(u => /^https?:\/\//i.test(u))
    readonly property bool configured: list.length > 0
    property var cache: ({})       // link -> eventos

    function merge() {
        const all = []
        for (const url of list) for (const e of (cache[url] || [])) all.push(e)
        all.sort((a, b) => a.start - b.start)
        events = all
    }
    function setError(url, message) {
        const e = Object.assign({}, feed.errors)
        if (message) e[url] = message; else delete e[url]
        feed.errors = e
    }
    function load(url) {
        const from = TP.startOfDay(Date.now()) - 86400000
        const to = from + 70 * 86400000
        const xhr = new XMLHttpRequest()
        xhr.timeout = 20000
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200 && xhr.responseText.indexOf("BEGIN:VCALENDAR") >= 0) {
                try {
                    const c = Object.assign({}, feed.cache)
                    c[url] = TP.parseIcs(xhr.responseText, from, to, url)
                    feed.cache = c
                    feed.setError(url, "")
                    feed.merge()
                } catch (e) { feed.setError(url, "Não consegui ler a agenda.") }
            } else feed.setError(url, xhr.status === 0 ? "Sem conexão com a agenda." : "A agenda respondeu " + xhr.status + ".")
        }
        xhr.open("GET", url)
        xhr.send()
    }
    function refresh() { for (const u of list) load(u) }

    onListChanged: { merge(); refresh() }
    Component.onCompleted: refresh()
    Timer { interval: 900000; running: feed.configured; repeat: true; onTriggered: feed.refresh() }
}
