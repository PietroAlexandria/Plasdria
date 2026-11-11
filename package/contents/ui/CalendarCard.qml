import QtQuick
import QtQuick.Layouts
import "timeparse.js" as TP

// Calendário do mês com navegação; hoje destacado.
Card {
    id: card
    title: monthNames[shown.getMonth()] + " " + shown.getFullYear()
    icon: "view-calendar-symbolic"
    stretch: true
    readonly property var monthNames: ["Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho", "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"]
    // Eventos das agendas configuradas (veja IcsFeed.qml) e se há alguma agenda.
    property var events: []
    property bool feedConfigured: false
    property string feedStatus: ""
    property date today: new Date()
    property date selected: new Date()
    readonly property var eventsByDay: {
        const map = {}
        for (const e of events) {
            // Evento de dia inteiro que dura vários dias aparece em cada um deles.
            let day = new Date(TP.startOfDay(e.start))
            const last = Math.max(e.start, e.end - (e.allDay ? 1 : 0))
            for (let guard = 0; day.getTime() <= last && guard < 40; ++guard) {
                const key = day.toDateString()
                ;(map[key] = map[key] || []).push(e)
                day = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1)
            }
        }
        for (const k in map) map[k].sort((a, b) => a.start - b.start)
        return map
    }
    readonly property var dayEvents: eventsByDay[selected.toDateString()] || []
    readonly property bool selectedIsToday: selected.toDateString() === today.toDateString()
    readonly property string selectedLabel: selectedIsToday ? "Hoje" : selected.toLocaleDateString(Qt.locale("pt_BR"), "dddd, d 'de' MMMM")
    property date shown: new Date(today.getFullYear(), today.getMonth(), 1)
    Timer { interval: 60000; running: true; repeat: true; onTriggered: { const n = new Date(); if (n.getDate() !== card.today.getDate()) { card.today = n; card.selected = n } } }

    readonly property var cells: {
        const first = new Date(shown.getFullYear(), shown.getMonth(), 1)
        const start = new Date(first); start.setDate(1 - first.getDay())
        const list = []
        for (let i = 0; i < 42; ++i) {
            const d = new Date(start); d.setDate(start.getDate() + i)
            list.push({ms: d.getTime(), key: d.toDateString(), day: d.getDate(), inMonth: d.getMonth() === shown.getMonth(),
                       isToday: d.toDateString() === today.toDateString(), weekend: d.getDay() === 0 || d.getDay() === 6})
        }
        // Remove a última semana quando ela é toda do mês seguinte.
        return list[35].inMonth ? list : list.slice(0, 35)
    }
    readonly property string footer: {
        const startOfYear = new Date(today.getFullYear(), 0, 1)
        const dayOfYear = Math.floor((today - startOfYear) / 86400000) + 1
        const daysInYear = (new Date(today.getFullYear(), 1, 29).getMonth() === 1) ? 366 : 365
        const week = Math.ceil((dayOfYear + startOfYear.getDay()) / 7)
        return "Semana " + week + " · dia " + dayOfYear + " de " + daysInYear
    }
    function move(delta) { shown = new Date(shown.getFullYear(), shown.getMonth() + delta, 1) }

    actions: [
        IconButton { t: card.t; icon: "go-previous"; size: 22; tip: "Mês anterior"; onClicked: card.move(-1) },
        IconButton { t: card.t; icon: "go-jump-today"; size: 22; tip: "Hoje"; onClicked: { card.shown = new Date(card.today.getFullYear(), card.today.getMonth(), 1); card.selected = new Date() } },
        IconButton { t: card.t; icon: "go-next"; size: 22; tip: "Próximo mês"; onClicked: card.move(1) }
    ]

    GridLayout {
        Layout.fillWidth: true; Layout.fillHeight: true
        columns: 7; columnSpacing: 0; rowSpacing: 0
        Repeater {
            model: ["D", "S", "T", "Q", "Q", "S", "S"]
            delegate: Text {
                required property string modelData
                text: modelData; color: card.t.faint; font.pixelSize: 10; font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true; Layout.preferredHeight: 18
            }
        }
        Repeater {
            model: card.cells
            delegate: Item {
                required property var modelData
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.preferredHeight: 22; Layout.minimumHeight: 20; Layout.maximumHeight: 40
                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height, 26); height: width; radius: width / 2
                    color: modelData.isToday ? card.t.accent : "transparent"
                    border.color: !modelData.isToday && modelData.key === card.selected.toDateString() ? card.t.accentLine : "transparent"; border.width: 1.5
                }
                Rectangle {   // há eventos neste dia
                    visible: !!card.eventsByDay[modelData.key]
                    width: 4; height: 4; radius: 2
                    anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: Math.max(0, (parent.height - 26) / 2 - 3)
                    color: modelData.isToday ? "#0b0f18" : card.t.accent
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: card.selected = new Date(modelData.ms) }
                Text {
                    anchors.centerIn: parent
                    text: modelData.day
                    font.pixelSize: 11; font.weight: modelData.isToday ? Font.Bold : Font.Normal
                    color: modelData.isToday ? "#0b0f18" : !modelData.inMonth ? card.t.faint : modelData.weekend ? card.t.muted : card.t.ink
                }
            }
        }
    }
    // Agenda do dia escolhido
    Rectangle { Layout.fillWidth: true; height: 1; color: card.t.border; visible: card.feedConfigured || card.events.length > 0 }
    Text { visible: card.feedConfigured; text: card.selectedLabel; color: card.t.muted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 0.6; font.capitalization: Font.AllUppercase }
    Repeater {
        model: card.dayEvents.slice(0, 4)
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true; spacing: 8
            Rectangle { width: 3; Layout.fillHeight: true; Layout.minimumHeight: 16; radius: 1.5; color: card.t.accent }
            Text { text: modelData.allDay ? "dia todo" : TP.formatDue(modelData.start, card.today.getTime()).split(" ")[1]; color: card.t.accent; font.pixelSize: 11; font.weight: Font.DemiBold; Layout.preferredWidth: 50 }
            Text { text: modelData.title + (modelData.location ? " · " + modelData.location : ""); color: card.t.ink; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
        }
    }
    Text { visible: card.feedConfigured && card.dayEvents.length > 4; text: "+ " + (card.dayEvents.length - 4) + " eventos"; color: card.t.faint; font.pixelSize: 10 }
    Text { visible: card.feedConfigured && card.dayEvents.length === 0 && card.feedStatus === ""; text: "Nenhum evento"; color: card.t.faint; font.pixelSize: 11 }
    Text { visible: card.feedStatus !== ""; text: card.feedStatus; color: card.t.warn; font.pixelSize: 10; wrapMode: Text.Wrap; Layout.fillWidth: true }
    Text { visible: !card.feedConfigured; text: "Dica: cole o link iCal da sua agenda (Google, Nextcloud…) em Configurar → Geral para ver seus eventos aqui."; color: card.t.faint; font.pixelSize: 10; wrapMode: Text.Wrap; Layout.fillWidth: true }
    Text { text: card.footer; color: card.t.faint; font.pixelSize: 10 }
}
