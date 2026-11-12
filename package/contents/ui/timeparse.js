.pragma library

// Utilidades de data: horário em frases ("amanhã 9h", "em 10 min"), formatação de prazos
// e leitura de agendas no formato iCalendar (.ics).

var WEEKDAYS = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]
var SHORT_DAYS = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]

// \b do JavaScript só entende letras sem acento; estes limites funcionam com "às", "amanhã"…
var B = "(?:^|[^A-Za-zÀ-ÿ0-9_])"
var E = "(?![A-Za-zÀ-ÿ0-9_])"

function pad(n) { return (n < 10 ? "0" : "") + n }
function clock(d) { return pad(d.getHours()) + ":" + pad(d.getMinutes()) }
function startOfDay(ms) { var d = new Date(ms); d.setHours(0, 0, 0, 0); return d.getTime() }

// Entende prazos escritos à mão. Devolve o texto sem o trecho do prazo e o instante (ms; 0 = sem prazo).
//   "ligar para o João às 15:30"   "tomar remédio em 20 min"   "reunião amanhã 9h"   "dentista sexta 14h30"
function parseWhen(input, nowMs) {
    var text = String(input)
    var now = new Date(nowMs)
    var m

    // Daqui a pouco: "em 10 min", "em 2h".
    m = new RegExp(B + "em\\s+(\\d+)\\s*(min(?:uto)?s?|m|h(?:ora)?s?)" + E, "i").exec(text)
    if (m) {
        var n = parseInt(m[1])
        var minutes = /^h/i.test(m[2]) ? n * 60 : n
        return {text: clean(text.replace(m[0], " ")), due: nowMs + minutes * 60000}
    }

    var dayOffset = -1
    var weekday = -1
    var tomorrow = new RegExp(B + "amanh[ãa]" + E, "i"), today = new RegExp(B + "hoje" + E, "i")
    if (tomorrow.test(text)) { dayOffset = 1; text = text.replace(tomorrow, " ") }
    else if (today.test(text)) { dayOffset = 0; text = text.replace(today, " ") }
    else {
        for (var i = 0; i < 7 && weekday < 0; ++i) {
            var re = new RegExp(B + WEEKDAYS[i].replace("ç", "[çc]").replace("á", "[áa]") + "(?:-feira)?" + E, "i")
            if (re.test(text)) { weekday = i; text = text.replace(re, " ") }
        }
    }

    var hour = -1, minute = 0
    m = new RegExp(B + "(?:[àa]s?\\s+)?(\\d{1,2})(?::(\\d{2})|h(\\d{2})?)" + E, "i").exec(text)
    if (m) { hour = parseInt(m[1]); minute = parseInt(m[2] || m[3] || "0"); text = text.replace(m[0], " ") }
    else {
        m = new RegExp(B + "[àa]s\\s+(\\d{1,2})" + E, "i").exec(text)
        if (m) { hour = parseInt(m[1]); text = text.replace(m[0], " ") }
    }
    if (hour > 23 || minute > 59) return {text: clean(String(input)), due: 0}

    if (hour < 0 && dayOffset < 0 && weekday < 0) return {text: clean(String(input)), due: 0}
    if (hour < 0) { hour = 9; minute = 0 }   // só o dia: 9h

    var d = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hour, minute, 0, 0)
    if (dayOffset >= 0) d.setDate(d.getDate() + dayOffset)
    else if (weekday >= 0) {
        var delta = (weekday - now.getDay() + 7) % 7
        d.setDate(d.getDate() + delta)
        if (d.getTime() <= nowMs) d.setDate(d.getDate() + 7)
    } else if (d.getTime() <= nowMs) d.setDate(d.getDate() + 1)   // só a hora, e já passou: amanhã
    return {text: clean(text), due: d.getTime()}
}

function clean(text) {
    return text.replace(/\s+/g, " ").replace(new RegExp(B + "(?:às?|em|para|no|na|de)\\s*$", "i"), "").replace(/^\s*[,.;:-]\s*/, "").trim()
}

// "hoje 15:30", "amanhã 09:00", "sex 14:30", "12/11 09:00"
function formatDue(ms, nowMs) {
    var d = new Date(ms)
    var days = Math.round((startOfDay(ms) - startOfDay(nowMs)) / 86400000)
    var when
    if (days === 0) when = "hoje"
    else if (days === 1) when = "amanhã"
    else if (days === -1) when = "ontem"
    else if (days > 1 && days < 7) when = SHORT_DAYS[d.getDay()]
    else when = pad(d.getDate()) + "/" + pad(d.getMonth() + 1)
    return when + " " + clock(d)
}

// ── iCalendar ─────────────────────────────────────────────────────────────

function unfold(text) { return String(text).replace(/\r?\n[ \t]/g, "") }

function unescapeText(v) { return String(v).replace(/\\n/gi, "\n").replace(/\\([,;\\])/g, "$1") }

// "DTSTART;TZID=America/Sao_Paulo:20261111T090000" -> {name, params, value}
function splitLine(line) {
    var colon = -1, quoted = false
    for (var i = 0; i < line.length; ++i) {
        var c = line[i]
        if (c === '"') quoted = !quoted
        else if (c === ":" && !quoted) { colon = i; break }
    }
    if (colon < 0) return null
    var left = line.slice(0, colon), value = line.slice(colon + 1)
    var parts = left.split(";")
    var params = {}
    for (var p = 1; p < parts.length; ++p) { var kv = parts[p].split("="); params[kv[0].toUpperCase()] = (kv[1] || "").replace(/"/g, "") }
    return {name: parts[0].toUpperCase(), params: params, value: value}
}

// Datas com "Z" são UTC; sem "Z" (inclusive com TZID) são lidas no fuso do computador.
function parseDate(value, params) {
    var m = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$/.exec(value.trim())
    if (!m) return null
    var allDay = !m[4] || (params && params.VALUE === "DATE")
    if (allDay) return {ms: new Date(+m[1], +m[2] - 1, +m[3]).getTime(), allDay: true}
    if (m[7]) return {ms: Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] || 0)), allDay: false}
    return {ms: new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] || 0)).getTime(), allDay: false}
}

function parseRule(text) {
    var rule = {}
    String(text).split(";").forEach(function (part) { var kv = part.split("="); rule[kv[0].toUpperCase()] = kv[1] || "" })
    return rule
}

var DAY_CODES = {SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6}

// Gera as datas de início de um evento (com repetição) dentro de [fromMs, toMs].
function occurrences(startMs, rule, exdates, fromMs, toMs) {
    var out = []
    var skip = {}
    exdates.forEach(function (x) { skip[x] = true })
    function add(ms) { if (ms >= fromMs && ms <= toMs && !skip[ms]) out.push(ms) }
    if (!rule || !rule.FREQ) { add(startMs); return out }

    var start = new Date(startMs)
    var interval = Math.max(1, parseInt(rule.INTERVAL || "1"))
    var count = rule.COUNT ? parseInt(rule.COUNT) : 0
    var until = 0
    if (rule.UNTIL) { var u = parseDate(rule.UNTIL, {}); if (u) until = u.allDay ? u.ms + 86399999 : u.ms }
    var limit = until ? Math.min(until, toMs) : toMs
    var produced = 0
    var byday = rule.BYDAY ? rule.BYDAY.split(",").map(function (x) { return DAY_CODES[x.slice(-2)] }).filter(function (x) { return x !== undefined }) : []
    var h = start.getHours(), mi = start.getMinutes(), s = start.getSeconds()

    function emit(d) {   // devolve false quando acabou
        var ms = d.getTime()
        if (ms < startMs) return true
        if (ms > limit) return false
        produced++
        if (count && produced > count) return false
        add(ms)
        return true
    }

    var guard = 0
    if (rule.FREQ === "DAILY") {
        for (var d = new Date(start); guard < 6000; d.setDate(d.getDate() + interval), ++guard) if (!emit(new Date(d))) break
    } else if (rule.FREQ === "WEEKLY") {
        var days = byday.length ? byday.slice().sort() : [start.getDay()]
        var weekStart = new Date(start.getFullYear(), start.getMonth(), start.getDate() - start.getDay(), h, mi, s)
        for (var w = new Date(weekStart); guard < 3000; w.setDate(w.getDate() + 7 * interval), ++guard) {
            var stop = false
            for (var k = 0; k < days.length; ++k) {
                var day = new Date(w.getFullYear(), w.getMonth(), w.getDate() + days[k], h, mi, s)
                if (!emit(day)) { stop = true; break }
            }
            if (stop) break
        }
    } else if (rule.FREQ === "MONTHLY") {
        var dom = rule.BYMONTHDAY ? parseInt(rule.BYMONTHDAY) : start.getDate()
        for (var mo = 0; guard < 1500; mo += interval, ++guard) {
            var dd = new Date(start.getFullYear(), start.getMonth() + mo, dom, h, mi, s)
            if (dd.getDate() !== dom) continue   // mês sem esse dia
            if (!emit(dd)) break
        }
    } else if (rule.FREQ === "YEARLY") {
        for (var y = 0; guard < 300; y += interval, ++guard) {
            var yd = new Date(start.getFullYear() + y, start.getMonth(), start.getDate(), h, mi, s)
            if (yd.getMonth() !== start.getMonth()) continue
            if (!emit(yd)) break
        }
    } else add(startMs)
    return out
}

// Lê um arquivo .ics e devolve os eventos que acontecem entre fromMs e toMs, em ordem.
function parseIcs(text, fromMs, toMs, source) {
    var lines = unfold(text).split(/\r?\n/)
    var blocks = [], cur = null
    for (var i = 0; i < lines.length; ++i) {
        var line = lines[i]
        if (line === "BEGIN:VEVENT") cur = []
        else if (line === "END:VEVENT") { if (cur) blocks.push(cur); cur = null }
        else if (cur && line) cur.push(line)
    }
    var overrides = {}
    var parsed = blocks.map(function (block) {
        var ev = {exdates: [], title: "", uid: "", location: ""}
        block.forEach(function (raw) {
            var f = splitLine(raw); if (!f) return
            switch (f.name) {
            case "SUMMARY": ev.title = unescapeText(f.value); break
            case "LOCATION": ev.location = unescapeText(f.value); break
            case "UID": ev.uid = f.value; break
            case "STATUS": ev.cancelled = f.value.toUpperCase() === "CANCELLED"; break
            case "DTSTART": ev.start = parseDate(f.value, f.params); break
            case "DTEND": ev.end = parseDate(f.value, f.params); break
            case "RRULE": ev.rule = parseRule(f.value); break
            case "RECURRENCE-ID": ev.recurrence = parseDate(f.value, f.params); break
            case "EXDATE": f.value.split(",").forEach(function (v) { var d = parseDate(v, f.params); if (d) ev.exdates.push(d.ms) }); break
            }
        })
        if (ev.recurrence) overrides[ev.uid + "|" + ev.recurrence.ms] = true
        return ev
    })

    var events = []
    parsed.forEach(function (ev) {
        if (!ev.start || ev.cancelled) return
        var length = ev.end ? Math.max(0, ev.end.ms - ev.start.ms) : (ev.start.allDay ? 86400000 : 0)
        var rule = ev.recurrence ? null : ev.rule
        // Eventos longos que começaram antes da janela também contam.
        occurrences(ev.start.ms, rule, ev.exdates, fromMs - length, toMs).forEach(function (ms) {
            if (!ev.recurrence && overrides[ev.uid + "|" + ms]) return
            events.push({title: ev.title || "(sem título)", start: ms, end: ms + length, allDay: ev.start.allDay,
                         location: ev.location, source: source || ""})
        })
    })
    events.sort(function (a, b) { return a.start - b.start })
    return events
}

// Alarmes: quais lembretes venceram e ainda não avisaram. Devolve a lista atualizada (marcada como avisada),
// o que notificar e se algo mudou. Lembretes vencidos há mais de 6 h são marcados sem notificar
// (o widget estava fechado) para não despejar avisos antigos.
function dueReminders(list, nowMs) {
    var notify = [], changed = false
    var updated = list.map(function (item) {
        if (item.done || !(item.due > 0) || item.notified || item.due > nowMs) return item
        changed = true
        if (nowMs - item.due < 6 * 3600 * 1000) notify.push(item.text)
        return Object.assign({}, item, {notified: true})
    })
    return {list: updated, notify: notify, changed: changed}
}

// Eventos da agenda que começam dentro de leadMs e ainda não foram avisados (eventos de dia inteiro não avisam).
// `seen` guarda o que já foi avisado (chave = título + início) para não repetir; devolve o novo `seen`,
// já sem entradas antigas.
function upcomingEvents(events, nowMs, leadMs, seen) {
    var notify = [], next = {}
    for (var key in seen) if (seen[key] > nowMs - 3600000) next[key] = seen[key]
    if (leadMs > 0) events.forEach(function (e) {
        if (e.allDay || e.start <= nowMs || e.start > nowMs + leadMs) return
        var key = e.title + "|" + e.start
        if (next[key]) return
        next[key] = e.start
        notify.push({title: e.title, start: e.start, location: e.location, minutes: Math.max(1, Math.round((e.start - nowMs) / 60000))})
    })
    return {notify: notify, seen: next}
}

// ── Resumo do dia ───────────────────────────────────────────────────────────

function dayKey(ms) { var d = new Date(ms); return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate() }

// Hora de avisar o resumo: a partir de `hour` (0–23; -1 desliga), por até 4 h, uma vez por dia (`lastDay` guarda o dia).
function summaryDue(nowMs, hour, lastDay) {
    if (!(hour >= 0)) return false
    var h = new Date(nowMs).getHours()
    return h >= hour && h < hour + 4 && dayKey(nowMs) !== lastDay
}

// Monta o resumo do dia a partir do que o widget já sabe. Tudo em texto simples, sem IA:
// o.events (da agenda), o.reminders (lista salva), o.weather ({place, temp, summary, high, low, rain, uv}).
// Devolve {sections: [{kind, title, lines, empty}], brief, text}.
function daySummary(o) {
    var now = o.now, start = startOfDay(now), end = start + 86400000
    var limit = 6

    var evs = (o.events || []).filter(function (e) {
        return e.end > start && e.start < end && (e.allDay || Math.max(e.end, e.start) >= now)
    }).sort(function (a, b) { return (b.allDay ? 1 : 0) - (a.allDay ? 1 : 0) || a.start - b.start })
    var agendaLines = evs.slice(0, limit).map(function (e) {
        return (e.allDay ? "Dia todo" : clock(new Date(e.start))) + "  " + e.title + (e.location ? " · " + e.location : "")
    })
    if (evs.length > limit) agendaLines.push("e mais " + (evs.length - limit))

    var pending = (o.reminders || []).filter(function (r) { return !r.done })
    var overdue = pending.filter(function (r) { return r.due > 0 && r.due < now })
    var today = pending.filter(function (r) { return r.due >= now && r.due < end })
    var later = pending.length - overdue.length - today.length
    var remLines = []
    overdue.forEach(function (r) { remLines.push("Atrasado  " + r.text) })
    today.forEach(function (r) { remLines.push(clock(new Date(r.due)) + "  " + r.text) })
    var shownRem = remLines.slice(0, limit)
    if (remLines.length > limit) shownRem.push("e mais " + (remLines.length - limit))
    if (later > 0) shownRem.push(later + (later === 1 ? " lembrete sem data para hoje" : " lembretes sem data para hoje"))

    var w = o.weather || {}
    var wLines = []
    if (w.temp) {
        wLines.push((w.place ? w.place + " · " : "") + w.temp + (w.summary ? " · " + w.summary : ""))
        var parts = []
        if (w.high > -999 && w.low > -999) parts.push("máx " + w.high + "° · mín " + w.low + "°")
        if (w.rain >= 0) parts.push("chuva " + w.rain + "%")
        if (w.uv >= 6) parts.push("UV " + w.uv + " (alto)")
        if (parts.length) wLines.push(parts.join(" · "))
        if (w.rain >= 60) wLines.push("Leve guarda-chuva.")
        else if (w.high >= 33) wLines.push("Dia quente: beba água.")
    }

    var sections = [
        {kind: "agenda", title: "Agenda de hoje", lines: agendaLines, empty: "Nada marcado para hoje."},
        {kind: "reminders", title: "Lembretes", lines: shownRem, empty: "Nenhum lembrete pendente."},
        {kind: "weather", title: "Clima", lines: wLines, empty: "Clima indisponível."}
    ]
    var briefParts = []
    briefParts.push(evs.length === 0 ? "sem eventos" : evs.length + (evs.length === 1 ? " evento" : " eventos"))
    var urgent = overdue.length + today.length
    briefParts.push(urgent === 0 ? "sem lembretes para hoje" : urgent + (urgent === 1 ? " lembrete" : " lembretes") + (overdue.length ? " (" + overdue.length + " atrasado" + (overdue.length === 1 ? "" : "s") + ")" : ""))
    if (w.temp) briefParts.push(w.temp + (w.rain >= 40 ? ", chuva " + w.rain + "%" : ""))
    var brief = briefParts.join(" · ")
    var text = sections.map(function (s) {
        return s.title + ":\n" + (s.lines.length ? s.lines.map(function (l) { return "- " + l }).join("\n") : "- " + s.empty)
    }).join("\n\n")
    return {sections: sections, brief: brief, text: text}
}
