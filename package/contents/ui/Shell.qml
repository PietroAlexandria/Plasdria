import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as B
import org.kde.kirigami as Kirigami

// Layout principal, com o painel geral (horário, cidade, clima) como base.
//  largo  (≥ 1100): painel geral em cima; embaixo colunas de cartões EDITÁVEIS; clima no rodapé
//  médio  (≥ 720):  painel + cartões roláveis à esquerda, chat à direita
//  estreito:        abas Painel / Chat
//
// No layout largo o usuário reorganiza na mão: arrasta cartões entre colunas, oculta/mostra
// cartões e puxa as divisões entre as colunas. O arranjo fica salvo em cfg.layout (JSON).
Item {
    id: shell
    required property var t
    required property var client
    required property var dash
    required property var media
    required property var net
    required property var cfg
    property bool editing: false
    property var sys: null          // controles do sistema (áudio, brilho, Bluetooth, processos, GPU, atalhos)
    signal saveShortcuts(string json)
    // Eventos das agendas iCal configuradas (veja IcsFeed.qml).
    property var events: []
    property bool feedConfigured: false
    property string feedStatus: ""
    signal saveReminders(string json)
    signal saveLayout(string json)
    signal editRequested(bool on)

    // Largo só quando cabe confortável: poucas alturas viram o layout médio, que rola.
    readonly property string mode: width >= 1100 && height >= 700 ? "wide" : width >= 720 ? "medium" : "narrow"
    property int tab: 0   // estreito: 0 = Painel, 1 = Chat
    property var wideChat: null
    function focusChat() {
        if (mode === "narrow") tab = 1
        Qt.callLater(() => { const c = mode === "wide" ? wideChat : (loader.item ? loader.item.chat : null); if (c) c.focusInput() })
    }

    // ── Arranjo dos cartões ────────────────────────────────────────────────
    readonly property var allIds: ["system", "devices", "network", "chat", "media", "calendar", "reminders", "news", "audio", "bluetooth", "top", "gpu", "shortcuts"]
    // Cartões novos começam ocultos: aparecem na barra de edição (＋) para você escolher onde ficam.
    readonly property var newIds: ["audio", "bluetooth", "top", "gpu", "shortcuts"]
    readonly property var names: ({system: "Sistema", devices: "Dispositivos", network: "Rede", chat: "Chat · " + shell.client.providerName,
                                   media: "Música", calendar: "Calendário", reminders: "Lembretes", news: "Notícias",
                                   audio: "Áudio e brilho", bluetooth: "Bluetooth", top: "Maiores consumidores", gpu: "GPU", shortcuts: "Atalhos"})
    readonly property var defaultCols: [["system", "devices", "network"], ["chat"], ["media", "calendar"], ["reminders", "news"]]
    readonly property var defaultWeights: [0.95, 1.35, 1, 1]

    property var colIds: defaultCols
    property var colW: defaultWeights
    property var hiddenIds: newIds.slice()

    function cardOn(id) {
        switch (id) {
        case "system": return !!cfg.showSystem
        case "devices": return !!cfg.showConnections
        case "network": return !!cfg.showNetwork
        case "media": return !!cfg.showMedia
        case "calendar": return cfg.showCalendar !== false
        case "reminders": return !!cfg.showReminders
        case "news": return !!cfg.showNews
        case "audio": return !!cfg.showAudio && !!sys
        case "bluetooth": return !!cfg.showBluetooth && !!sys
        case "top": return !!cfg.showTop && !!sys
        case "gpu": return !!cfg.showGpu && !!sys
        case "shortcuts": return !!cfg.showShortcuts && !!sys
        default: return true
        }
    }
    function shownIds(col) { return (colIds[col] || []).filter(id => cardOn(id)) }
    // Ordem única (colunas da esquerda para a direita) para os layouts empilhados.
    readonly property var stackOrder: { const out = []; for (let i = 0; i < colIds.length; ++i) for (const id of shownIds(i)) if (id !== "chat") out.push(id); return out }
    readonly property var hiddenEnabled: hiddenIds.filter(id => cardOn(id))

    function applyLayout(text) {
        let cols = defaultCols.map(c => c.slice()), weights = defaultWeights.slice(), hidden = newIds.slice()
        try {
            const o = JSON.parse(text)
            if (Array.isArray(o.cols) && o.cols.length > 0 && o.cols.length <= 8) {
                const seen = {}
                const parsed = [], w = []
                for (const c of o.cols) {
                    const ids = (Array.isArray(c.c) ? c.c : []).filter(id => allIds.indexOf(id) >= 0 && !seen[id] && (seen[id] = true))
                    parsed.push(ids)
                    w.push(typeof c.w === "number" && c.w >= 0.3 && c.w <= 6 ? c.w : 1)
                }
                hidden = (Array.isArray(o.hidden) ? o.hidden : []).filter(id => allIds.indexOf(id) >= 0 && !seen[id] && id !== "chat" && (seen[id] = true))
                // Cartões que não aparecem no arquivo (versões novas) ficam ocultos, o chat nunca some.
                const missing = allIds.filter(id => !seen[id])
                if (missing.indexOf("chat") >= 0) { parsed[0].push("chat"); missing.splice(missing.indexOf("chat"), 1) }
                hidden = hidden.concat(missing)
                cols = parsed; weights = w
            }
        } catch (e) {}
        colIds = cols; colW = weights; hiddenIds = hidden
    }
    readonly property string layoutText: cfg.layout || ""
    onLayoutTextChanged: applyLayout(layoutText)
    Component.onCompleted: applyLayout(layoutText)
    function persist() { saveLayout(JSON.stringify({cols: colIds.map((c, i) => ({w: Math.round(colW[i] * 1000) / 1000, c: c})), hidden: hiddenIds})) }

    function moveCard(id, col, index) {
        const cols = colIds.map(c => c.filter(x => x !== id))
        const shown = cols[col].filter(x => cardOn(x))
        let at
        if (shown.length === 0) at = cols[col].length
        else if (index >= shown.length) at = cols[col].indexOf(shown[shown.length - 1]) + 1
        else at = cols[col].indexOf(shown[index])
        cols[col].splice(at, 0, id)
        hiddenIds = hiddenIds.filter(x => x !== id)
        colIds = cols
        persist()
    }
    function hideCard(id) {
        if (id === "chat") return
        colIds = colIds.map(c => c.filter(x => x !== id))
        hiddenIds = hiddenIds.concat([id])
        persist()
    }
    function showCard(id) {
        // Vai para a coluna com menos cartões.
        let best = 0
        for (let i = 1; i < colIds.length; ++i) if (shownIds(i).length < shownIds(best).length) best = i
        moveCard(id, best, 999)
    }
    // Nos layouts empilhados: troca o cartão de lugar com o vizinho da pilha.
    function moveInStack(id, delta) {
        const order = stackOrder
        const i = order.indexOf(id), j = i + delta
        if (i < 0 || j < 0 || j >= order.length) return
        const cols = colIds.map(c => c.slice())
        const find = x => { for (let c = 0; c < cols.length; ++c) { const k = cols[c].indexOf(x); if (k >= 0) return [c, k] } return null }
        const a = find(id), b = find(order[j])
        if (!a || !b) return
        cols[a[0]][a[1]] = order[j]; cols[b[0]][b[1]] = id
        colIds = cols
        persist()
    }
    function resetLayout() { colIds = defaultCols.map(c => c.slice()); colW = defaultWeights.slice(); hiddenIds = newIds.slice(); persist() }

    // Arrasto de um cartão (coordenadas do Shell).
    property string dragId: ""
    property real dragX: 0
    property real dragY: 0
    signal dragFinished()

    Rectangle { anchors.fill: parent; radius: 20; color: shell.t.background; border.color: shell.t.border }

    Row {
        visible: shell.mode === "narrow"
        anchors.top: parent.top; anchors.topMargin: 12; anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4; z: 2
        Repeater {
            model: ["Painel", "Chat"]
            delegate: Rectangle {
                required property string modelData
                required property int index
                width: 104; height: 28; radius: 14
                color: shell.tab === index ? shell.t.accentSoft : "transparent"
                border.color: shell.tab === index ? shell.t.accentLine : shell.t.border
                Text { anchors.centerIn: parent; text: modelData; color: shell.tab === index ? shell.t.accent : shell.t.muted; font.pixelSize: 12; font.weight: Font.DemiBold }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: shell.tab = index }
            }
        }
    }

    Loader {
        id: loader
        anchors.fill: parent
        anchors.margins: 12
        anchors.topMargin: shell.mode === "narrow" ? 50 : 12
        sourceComponent: shell.mode === "wide" ? wideLayout : shell.mode === "medium" ? mediumLayout : narrowLayout
    }

    // Cartão sendo arrastado.
    Rectangle {
        visible: shell.dragId !== ""
        z: 100
        x: shell.dragX - width / 2; y: shell.dragY - height / 2
        width: 190; height: 34; radius: 17
        color: shell.t.cardRaised; border.color: shell.t.accent; border.width: 2
        opacity: 0.95
        Text { anchors.centerIn: parent; text: shell.names[shell.dragId] || ""; color: shell.t.ink; font.pixelSize: 12; font.weight: Font.DemiBold }
    }

    // ── Cartões ────────────────────────────────────────────────────────────
    Component { id: compSystem; SystemCard { t: shell.t; dash: shell.dash; sys: shell.sys } }
    Component { id: compDevices; ConnectionsCard { t: shell.t; dash: shell.dash } }
    Component { id: compNetwork; NetworkCard { t: shell.t; net: shell.net } }
    Component { id: compMedia; MediaCard { t: shell.t; media: shell.media } }
    Component { id: compCalendar; CalendarCard { t: shell.t; events: shell.events; feedConfigured: shell.feedConfigured; feedStatus: shell.feedStatus } }
    Component { id: compReminders; RemindersCard { t: shell.t; stored: shell.cfg.reminders || "[]"; onSave: json => shell.saveReminders(json) } }
    Component { id: compNews; NewsCard { t: shell.t; dash: shell.dash } }
    Component { id: compAudio; AudioCard { t: shell.t; sys: shell.sys } }
    Component { id: compBluetooth; BluetoothCard { t: shell.t; sys: shell.sys } }
    Component { id: compTop; TopCard { t: shell.t; sys: shell.sys } }
    Component { id: compGpu; GpuCard { t: shell.t; sys: shell.sys; dash: shell.dash } }
    Component { id: compShortcuts; ShortcutsCard { t: shell.t; sys: shell.sys; stored: shell.cfg.shortcuts || "[]"; onSave: json => shell.saveShortcuts(json) } }
    Component { id: compChat; ChatView { id: wideChatView; t: shell.t; client: shell.client; Component.onCompleted: shell.wideChat = wideChatView } }
    function factory(id) {
        switch (id) {
        case "system": return compSystem
        case "devices": return compDevices
        case "network": return compNetwork
        case "media": return compMedia
        case "calendar": return compCalendar
        case "reminders": return compReminders
        case "news": return compNews
        case "chat": return compChat
        case "audio": return compAudio
        case "bluetooth": return compBluetooth
        case "top": return compTop
        case "gpu": return compGpu
        case "shortcuts": return compShortcuts
        }
        return null
    }

    component Chip: Rectangle {
        id: chip
        property string text
        property bool solid: false
        property bool muted: false
        signal clicked()
        implicitHeight: 26; implicitWidth: chipLabel.implicitWidth + 22; radius: 13
        color: solid ? shell.t.accent : chipHover.hovered ? shell.t.cardRaised : "transparent"
        border.color: solid ? "transparent" : muted ? shell.t.border : shell.t.accentLine
        Text { id: chipLabel; anchors.centerIn: parent; text: chip.text; font.pixelSize: 11; font.weight: chip.muted ? Font.Normal : Font.DemiBold
            color: chip.solid ? "#101119" : chip.muted ? shell.t.muted : shell.t.accent }
        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: chip.clicked() }
    }

    // Barra do modo de edição: dica, cartões ocultos (para trazer de volta), restaurar e concluir.
    component EditBar: Rectangle {
        id: eb
        property bool compact: false
        readonly property string hint: compact ? "Editando · use ▲ ▼ para mover e o olho para ocultar" : "Editando · arraste os cartões pelo nome e puxe as divisões entre as colunas"
        radius: compact ? 14 : 16; color: shell.t.accentSoft; border.color: shell.t.accentLine
        implicitHeight: compact ? stackBar.implicitHeight + 16 : 32
        RowLayout {
            visible: !eb.compact
            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 3; spacing: 6
            Text { text: eb.hint; color: shell.t.ink; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true; Layout.minimumWidth: 80 }
            Repeater { model: shell.hiddenEnabled; delegate: Chip { required property string modelData; text: "＋ " + (shell.names[modelData] || modelData); onClicked: shell.showCard(modelData) } }
            Chip { text: "Restaurar padrão"; muted: true; onClicked: shell.resetLayout() }
            Chip { text: "Concluir"; solid: true; onClicked: shell.editRequested(false) }
        }
        ColumnLayout {
            id: stackBar
            visible: eb.compact
            anchors.fill: parent; anchors.margins: 8; spacing: 6
            Text { text: eb.hint; color: shell.t.ink; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }
            Flow {
                Layout.fillWidth: true; spacing: 6
                Repeater { model: shell.hiddenEnabled; delegate: Chip { required property string modelData; text: "＋ " + (shell.names[modelData] || modelData); onClicked: shell.showCard(modelData) } }
                Chip { text: "Restaurar padrão"; muted: true; onClicked: shell.resetLayout() }
                Chip { text: "Concluir"; solid: true; onClicked: shell.editRequested(false) }
            }
        }
    }

    // Um cartão dentro de uma coluna (ou da pilha), com a camada de edição por cima.
    component Slot: Loader {
        id: slot
        property string cardId
        property bool stacked: false
        property bool last: false
        sourceComponent: shell.factory(cardId)
        onLoaded: if (stacked && cardId === "news") item.listHeight = 300

        Layout.fillWidth: true
        // Altura declarada de forma explícita: dentro do layout o Loader não acompanha o implicitHeight sozinho.
        readonly property real wanted: item ? item.implicitHeight : 0
        Layout.preferredHeight: cardId === "chat" ? 300 : wanted
        Layout.minimumHeight: cardId === "chat" ? 300 : (stacked ? wanted : Math.min(wanted, 60))
        Layout.fillHeight: !stacked && (last || cardId === "chat")

        Item {
            id: overlay
            anchors.fill: parent
            visible: shell.editing
            z: 10
            opacity: shell.dragId === slot.cardId ? 0.35 : 1
            Rectangle { anchors.fill: parent; radius: shell.t.radius; color: Qt.rgba(shell.t.background.r, shell.t.background.g, shell.t.background.b, 0.66); border.color: shell.t.accentLine; border.width: 2 }
            MouseArea {
                anchors.fill: parent
                cursorShape: slot.stacked ? Qt.ArrowCursor : Qt.SizeAllCursor
                acceptedButtons: Qt.LeftButton
                onPressed: mouse => { if (slot.stacked) return; const p = mapToItem(shell, mouse.x, mouse.y); shell.dragX = p.x; shell.dragY = p.y; shell.dragId = slot.cardId }
                onPositionChanged: mouse => { if (!pressed || slot.stacked) return; const p = mapToItem(shell, mouse.x, mouse.y); shell.dragX = p.x; shell.dragY = p.y }
                onReleased: shell.dragFinished()
                onCanceled: shell.dragFinished()
            }
            Rectangle {
                anchors.centerIn: parent
                width: label.implicitWidth + 28; height: 30; radius: 15
                color: shell.t.cardRaised; border.color: shell.t.accentLine
                Row {
                    anchors.centerIn: parent; spacing: 6
                    Text { text: "⠿"; color: shell.t.accent; font.pixelSize: 15; anchors.verticalCenter: parent.verticalCenter }
                    Text { id: label; text: shell.names[slot.cardId] || ""; color: shell.t.ink; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            Row {
                anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 6; spacing: 4
                IconButton { visible: slot.stacked; t: shell.t; icon: "go-up"; size: 26; tip: "Mover para cima"; onClicked: shell.moveInStack(slot.cardId, -1) }
                IconButton { visible: slot.stacked; t: shell.t; icon: "go-down"; size: 26; tip: "Mover para baixo"; onClicked: shell.moveInStack(slot.cardId, 1) }
                IconButton { visible: slot.cardId !== "chat"; t: shell.t; icon: "view-hidden"; size: 26; tip: "Ocultar este cartão"; onClicked: shell.hideCard(slot.cardId) }
            }
        }
    }

    component Scroller: Flickable {
        clip: true; boundsBehavior: Flickable.StopAtBounds
        B.ScrollBar.vertical: B.ScrollBar { policy: B.ScrollBar.AsNeeded; width: 6 }
    }

    // Cartões reutilizados nos layouts empilhados (médio e estreito), na ordem escolhida.
    component CardStack: GridLayout {
        // Duas colunas quando sobra largura; uma só quando o espaço é curto.
        columns: width >= 640 ? 2 : 1
        columnSpacing: shell.t.gap; rowSpacing: shell.t.gap
        EditBar { visible: shell.editing; compact: true; Layout.fillWidth: true; Layout.columnSpan: parent.columns }
        Repeater {
            model: shell.stackOrder
            delegate: Slot {
                required property string modelData
                cardId: modelData; stacked: true
                Layout.preferredWidth: 100
                Layout.alignment: Qt.AlignTop
            }
        }
        WeatherFooter { t: shell.t; dash: shell.dash; compact: true; Layout.fillWidth: true; Layout.columnSpan: parent.columns }
    }

    Component {
        id: wideLayout
        Item {
            id: wide
            property var chat: shell.wideChat
            HeroPanel {
                id: hero
                width: parent.width
                t: shell.t; dash: shell.dash; client: shell.client; media: shell.media; net: shell.net; reminders: shell.cfg.reminders || "[]"; userName: shell.cfg.userName || ""; mode: "full"; editing: shell.editing; onEditRequested: shell.editRequested(true)
            }
            WeatherFooter {
                id: footer
                t: shell.t; dash: shell.dash
                width: parent.width
                y: parent.height - height
            }

            // Barra do modo de edição.
            property real barHeight: shell.editing ? 42 : 0
            Behavior on barHeight { NumberAnimation { duration: shell.t.animations ? 160 : 0; easing.type: Easing.OutCubic } }
            EditBar {
                id: bar
                visible: wide.barHeight > 1
                y: hero.height + shell.t.gap
                width: parent.width
                opacity: Math.min(1, wide.barHeight / 42)
            }

            // Colunas.
            Item {
                id: cols
                y: hero.height + shell.t.gap + wide.barHeight
                width: parent.width; height: footer.y - shell.t.gap - y

                function colVisible(i) { return shell.editing || shell.shownIds(i).length > 0 }
                readonly property int count: shell.colIds.length
                function visibleCount() { let n = 0; for (let i = 0; i < count; ++i) if (colVisible(i)) n++; return n }
                function totalWeight() { let s = 0; for (let i = 0; i < count; ++i) if (colVisible(i)) s += shell.colW[i]; return s }
                function available() { return width - shell.t.gap * Math.max(0, visibleCount() - 1) }
                function colWidth(i) { return colVisible(i) ? available() * shell.colW[i] / Math.max(0.01, totalWeight()) : 0 }
                function colX(i) { let x = 0; for (let j = 0; j < i; ++j) if (colVisible(j)) x += colWidth(j) + shell.t.gap; return x }
                function nextVisible(i) { for (let j = i + 1; j < count; ++j) if (colVisible(j)) return j; return -1 }

                // Onde o cartão arrastado cairia: coluna, posição e a linha indicadora.
                function dropTarget(p) {
                    let best = -1, bestDist = 1e9
                    for (let i = 0; i < count; ++i) {
                        if (!colVisible(i)) continue
                        const x0 = colX(i), x1 = x0 + colWidth(i)
                        const d = p.x < x0 ? x0 - p.x : p.x > x1 ? p.x - x1 : 0
                        if (d < bestDist) { bestDist = d; best = i }
                    }
                    if (best < 0) return null
                    const col = colRepeater.itemAt(best)
                    if (!col) return null
                    const slots = []
                    for (let k = 0; k < col.slotRepeater.count; ++k) { const s = col.slotRepeater.itemAt(k); if (s && s.cardId !== shell.dragId) slots.push(s) }
                    let index = 0
                    for (const s of slots) if (p.y > s.mapToItem(cols, 0, 0).y + s.height / 2) index++
                    let y
                    if (slots.length === 0) y = 4
                    else if (index === 0) y = slots[0].mapToItem(cols, 0, 0).y - shell.t.gap / 2
                    else y = slots[index - 1].mapToItem(cols, 0, 0).y + slots[index - 1].height + shell.t.gap / 2
                    return {col: best, index: index, x: colX(best), w: colWidth(best), y: y}
                }
                readonly property var target: shell.dragId !== "" ? dropTarget(cols.mapFromItem(shell, shell.dragX, shell.dragY)) : null

                Connections {
                    target: shell
                    function onDragFinished() {
                        const tg = cols.target
                        const id = shell.dragId
                        shell.dragId = ""
                        if (tg && id !== "") shell.moveCard(id, tg.col, tg.index)
                    }
                }

                Repeater {
                    id: colRepeater
                    model: cols.count
                    delegate: Item {
                        id: col
                        required property int index
                        property alias slotRepeater: slots
                        readonly property var ids: shell.shownIds(index)
                        visible: cols.colVisible(index)
                        x: cols.colX(index); width: cols.colWidth(index); height: cols.height

                        // Coluna vazia no modo de edição.
                        Rectangle {
                            visible: shell.editing && col.ids.length === 0
                            anchors.fill: parent; radius: shell.t.radius; color: "transparent"
                            border.color: shell.t.accentLine; border.width: 2
                            Text { anchors.centerIn: parent; text: "Solte um cartão aqui"; color: shell.t.faint; font.pixelSize: 12 }
                        }
                        Scroller {
                            id: scroller
                            anchors.fill: parent
                            contentHeight: Math.max(height, colLayout.implicitHeight)
                            ColumnLayout {
                                id: colLayout
                                width: scroller.width - (colLayout.implicitHeight > scroller.height ? 8 : 0)
                                height: scroller.contentHeight
                                spacing: shell.t.gap
                                Repeater {
                                    id: slots
                                    model: col.ids
                                    delegate: Slot { required property string modelData; required property int index; cardId: modelData; last: index === col.ids.length - 1 }
                                }
                            }
                        }
                    }
                }

                // Divisões arrastáveis entre colunas.
                Repeater {
                    model: shell.editing ? cols.count : 0
                    delegate: Item {
                        id: splitter
                        required property int index
                        readonly property int nextCol: cols.colVisible(index) ? cols.nextVisible(index) : -1
                        visible: nextCol >= 0
                        x: cols.colX(index) + cols.colWidth(index) + shell.t.gap / 2 - 8
                        width: 16; height: cols.height; z: 20
                        property real startX: 0
                        property real startA: 1
                        property real startB: 1
                        Rectangle { anchors.centerIn: parent; width: splitArea.pressed || splitArea.containsMouse ? 5 : 3; height: Math.min(parent.height, 120); radius: 3; color: shell.t.accent; opacity: splitArea.pressed ? 1 : 0.6 }
                        MouseArea {
                            id: splitArea
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.SplitHCursor
                            onPressed: mouse => { splitter.startX = mapToItem(shell, mouse.x, 0).x; splitter.startA = shell.colW[splitter.index]; splitter.startB = shell.colW[splitter.nextCol] }
                            onPositionChanged: mouse => {
                                if (!pressed) return
                                const dx = mapToItem(shell, mouse.x, 0).x - splitter.startX
                                const perWeight = cols.available() / Math.max(0.01, cols.totalWeight())
                                const min = 0.35
                                const dw = Math.max(min - splitter.startA, Math.min(splitter.startB - min, dx / perWeight))
                                const w = shell.colW.slice()
                                w[splitter.index] = splitter.startA + dw
                                w[splitter.nextCol] = splitter.startB - dw
                                shell.colW = w
                            }
                            onReleased: shell.persist()
                        }
                    }
                }

                // Indicador de onde o cartão será solto.
                Rectangle {
                    visible: cols.target !== null
                    z: 30
                    x: cols.target ? cols.target.x : 0; y: cols.target ? cols.target.y - 2 : 0
                    width: cols.target ? cols.target.w : 0; height: 4; radius: 2
                    color: shell.t.accent
                }
            }
        }
    }

    Component {
        id: mediumLayout
        Item {
            property var chat: chatView
            readonly property int chatWidth: Math.round(Math.max(330, Math.min(400, width * 0.42)))
            Scroller {
                id: scroller
                width: parent.width - chatWidth - shell.t.gap; height: parent.height
                contentHeight: column.implicitHeight
                ColumnLayout {
                    id: column
                    width: scroller.width - (scroller.contentHeight > scroller.height ? 8 : 0)
                    spacing: shell.t.gap
                    HeroPanel { t: shell.t; dash: shell.dash; client: shell.client; media: shell.media; net: shell.net; reminders: shell.cfg.reminders || "[]"; userName: shell.cfg.userName || ""; mode: "compact"; editing: shell.editing; onEditRequested: shell.editRequested(true); Layout.fillWidth: true }
                    CardStack { Layout.fillWidth: true }
                }
            }
            ChatView {
                id: chatView
                t: shell.t; client: shell.client
                x: parent.width - width; width: parent.chatWidth; height: parent.height
            }
        }
    }

    Component {
        id: narrowLayout
        Item {
            property var chat: chatView
            Scroller {
                id: scroller
                anchors.fill: parent
                visible: shell.tab === 0
                contentHeight: column.implicitHeight
                ColumnLayout {
                    id: column
                    width: scroller.width - (scroller.contentHeight > scroller.height ? 8 : 0)
                    spacing: shell.t.gap
                    HeroPanel { t: shell.t; dash: shell.dash; client: shell.client; media: shell.media; net: shell.net; reminders: shell.cfg.reminders || "[]"; userName: shell.cfg.userName || ""; mode: "stacked"; editing: shell.editing; onEditRequested: shell.editRequested(true); Layout.fillWidth: true }
                    CardStack { Layout.fillWidth: true }
                }
            }
            ChatView { id: chatView; anchors.fill: parent; visible: shell.tab === 1; t: shell.t; client: shell.client }
        }
    }
}
