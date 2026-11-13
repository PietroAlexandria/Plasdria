import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as B
import org.kde.kirigami as Kirigami
import "quickitems.js" as QI

// Configurações dentro do próprio widget (⚙ ao lado do logo). Tudo vale na hora e fica salvo
// nas configurações do Plasma; o que é mais raro (cidade, agenda, chaves) continua em "Mais opções…".
Item {
    id: panel
    required property var t
    required property var cfg
    required property var host       // o Shell: para mostrar/ocultar cartões no layout
    property string section: "appearance"
    signal closeRequested()
    signal moreRequested()

    readonly property var sections: [
        {id: "appearance", text: "Aparência", icon: "color-management"},
        {id: "cards", text: "Cartões", icon: "view-grid-symbolic"},
        {id: "quick", text: "Ações rápidas", icon: "configure-shortcuts"},
        {id: "sidebar", text: "Barra lateral", icon: "view-split-left-right"},
        {id: "general", text: "Geral", icon: "preferences-system-symbolic"}
    ]
    readonly property var cardKeys: ({system: "showSystem", devices: "showConnections", network: "showNetwork", media: "showMedia",
                                      calendar: "showCalendar", reminders: "showReminders", news: "showNews", audio: "showAudio",
                                      bluetooth: "showBluetooth", top: "showTop", gpu: "showGpu", shortcuts: "showShortcuts",
                                      speedtest: "showSpeedTest", clock: "showClock", day: "showDay", quick: "showQuick"})
    readonly property var accentColors: ["#3daee9", "#2bd9b0", "#8b7cff", "#5fd38a", "#f2b64c", "#ff7a6b", "#ff6fb5", "#c7cbd6"]
    readonly property var providers: [
        {value: "antigravity", text: "Antigravity"}, {value: "claude", text: "Claude"}, {value: "codex", text: "Codex"},
        {value: "gemini", text: "Gemini CLI"}, {value: "ollama", text: "Ollama"}, {value: "custom", text: "API Compatível"}]

    function set(key, value) { if (cfg[key] !== value) cfg[key] = value }
    function num(key, fallback) { const v = cfg[key]; return v === undefined || v === null ? fallback : v }

    // ── Barra lateral ──
    readonly property var sidebarParts: [
        {id: "clock", text: "Horário e data", icon: "clock"},
        {id: "weather", text: "Clima", icon: "weather-few-clouds-symbolic"},
        {id: "system", text: "Uso da CPU e da memória", icon: "cpu"},
        {id: "battery", text: "Bateria", icon: "battery-good-symbolic"},
        {id: "network", text: "Conexão", icon: "network-wireless-symbolic"},
        {id: "media", text: "Música", icon: "media-playback-start"},
        {id: "quick", text: "Ações rápidas", icon: "configure-shortcuts"},
        {id: "chat", text: "Botão de conversar", icon: "dialog-messages"}]
    readonly property var sidebarHidden: { try { const l = JSON.parse(cfg.sidebarHidden || "[]"); return Array.isArray(l) ? l : [] } catch (e) { return [] } }
    function toggleSidebarPart(id) {
        const l = sidebarHidden.slice(), i = l.indexOf(id)
        if (i >= 0) l.splice(i, 1); else l.push(id)
        set("sidebarHidden", JSON.stringify(l))
    }
    property string sidebarStatus: ""
    readonly property string sidebarState: host.sys ? (host.sys.sidebarState || "") : ""
    readonly property string sidebarEdge: host.sys ? (host.sys.sidebarEdge || "") : ""
    readonly property var busyEdges: host.sys && host.sys.sidebarBusyEdges ? host.sys.sidebarBusyEdges : []
    readonly property var edgeNames: ({right: "a direita", left: "a esquerda", top: "cima", bottom: "baixo"})
    function placeBar(edge) { sidebarStatus = sidebarState === "none" || sidebarState === "" ? "Criando…" : "Movendo…"; host.sys.createSidebar(edge, sidebarConfig()) }
    onSectionChanged: if (section === "sidebar" && host.sys && host.sys.refreshSidebar) host.sys.refreshSidebar()
    // A barra lateral é outra cópia do Plasdria: leva a aparência e o básico desta, sem repetir avisos.
    function sidebarConfig() {
        const groups = {
            General: ["userName", "autoLocation", "cityName", "cityLatitude", "cityLongitude", "defaultProvider", "defaultModel", "defaultEffort", "newsTopic"],
            Appearance: ["accentColor", "backgroundOpacity", "themeMode", "uiScale", "density", "iconScale", "animations"],
            Cards: ["quickItems", "sidebarHidden"]
        }
        const out = {}
        for (const g in groups) {
            out[g] = {}
            for (const k of groups[g]) if (cfg[k] !== undefined && cfg[k] !== null) out[g][k] = cfg[k]
        }
        // Resumo diário e alertas já saem desta cópia: a barra lateral não os repete.
        out.Data = {welcomeSeen: 99, summaryEnabled: false, alertsEnabled: false}
        return out
    }
    Connections {
        target: panel.host.sys
        ignoreUnknownSignals: true
        function onSidebarResult(status) {
            panel.sidebarStatus = status === "created" ? "Barra criada. Para mudar o tamanho, clique direito nela → Mostrar configurações do painel."
                : status === "moved" ? "Barra movida para " + (panel.edgeNames[panel.sidebarEdge] || "a nova borda") + "."
                : status === "exists" ? "A barra já está nessa borda."
                : status === "occupied" ? "Essa borda já tem outro painel (como a barra de tarefas). No Plasma, dois painéis na mesma borda ficam um por cima do outro: escolha outra borda."
                : status === "autohide" ? "Barra minimizada: ela se esconde e volta quando o mouse encosta na borda da tela."
                : status === "pinned" ? "Barra fixada: fica sempre à vista."
                : status === "removed" ? "Barra lateral removida."
                : status === "none" ? "Não há barra lateral para remover."
                : "Não deu certo. Confira se o qdbus6 está instalado (pacote qt6-tools)."
        }
    }

    // Cartões que dependem de um motor que não existe (ex.: na prévia) ficam apagados.
    function available(id) {
        if (["audio", "bluetooth", "top", "gpu", "shortcuts", "quick"].indexOf(id) >= 0) return !!host.sys
        if (id === "speedtest") return !!host.speed
        if (id === "clock") return !!host.clock
        return true
    }
    // Cartão "na tela": ligado nas configurações e posto no layout.
    function cardShown(id) { return host.cardOn(id) && host.hiddenIds.indexOf(id) < 0 }
    function setCard(id, on) {
        if (!on) { host.hideCard(id); return }
        set(cardKeys[id], true)
        Qt.callLater(() => { if (host.hiddenIds.indexOf(id) >= 0) host.showCard(id) })
    }

    Rectangle { anchors.fill: parent; radius: 20; color: Qt.rgba(0, 0, 0, 0.55) }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: panel.closeRequested() }

    Rectangle {
        id: box
        anchors.centerIn: parent
        width: Math.min(620, panel.width - 24); height: Math.min(580, panel.height - 24)
        radius: panel.t.radius; color: panel.t.card; border.color: panel.t.accentLine
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }   // cliques dentro não fecham

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 16; spacing: 12

            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Kirigami.Icon { source: "configure"; implicitWidth: 18; implicitHeight: 18; isMask: true; color: panel.t.accent }
                Text { text: "Configurações"; color: panel.t.ink; font.pixelSize: 17; font.weight: Font.DemiBold; Layout.fillWidth: true }
                IconButton { t: panel.t; icon: "window-close"; tip: "Fechar (Esc)"; onClicked: panel.closeRequested() }
            }

            // Seções
            Flow {
                Layout.fillWidth: true; spacing: 6
                Repeater {
                    model: panel.sections
                    delegate: Rectangle {
                        id: tab
                        required property var modelData
                        readonly property bool current: panel.section === modelData.id
                        width: tabRow.implicitWidth + 22; height: 30; radius: 15
                        color: current ? panel.t.accentSoft : tabHover.hovered ? panel.t.cardRaised : "transparent"
                        border.color: current ? panel.t.accentLine : panel.t.border
                        Row {
                            id: tabRow; anchors.centerIn: parent; spacing: 6
                            Kirigami.Icon { source: tab.modelData.icon; width: 14; height: 14; isMask: true; color: tab.current ? panel.t.accent : panel.t.muted; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: tab.modelData.text; color: tab.current ? panel.t.accent : panel.t.ink; font.pixelSize: 12; font.weight: tab.current ? Font.DemiBold : Font.Normal; anchors.verticalCenter: parent.verticalCenter }
                        }
                        HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: panel.section = tab.modelData.id }
                        Accessible.role: Accessible.PageTab
                        Accessible.name: modelData.text
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: panel.t.border }

            Flickable {
                id: flick
                Layout.fillWidth: true; Layout.fillHeight: true
                contentHeight: pages.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                B.ScrollBar.vertical: B.ScrollBar { policy: flick.contentHeight > flick.height ? B.ScrollBar.AsNeeded : B.ScrollBar.AlwaysOff }

                ColumnLayout {
                    id: pages
                    width: flick.width - 10
                    spacing: 14

                    // ── Aparência ─────────────────────────────────────────
                    ColumnLayout {
                        visible: panel.section === "appearance"
                        Layout.fillWidth: true; spacing: 14
                        Field {
                            label: "Tema"
                            Segmented {
                                options: [{value: "dark", text: "Escuro"}, {value: "light", text: "Claro"}, {value: "system", text: "Do sistema"}]
                                value: panel.cfg.themeMode || "dark"
                                onPicked: v => panel.set("themeMode", v)
                            }
                        }
                        Field {
                            label: "Tamanho geral"
                            hint: "Fontes, ícones e cartões juntos. Vale ao soltar a barra."
                            Slide { key: "uiScale"; from: 50; to: 160; step: 5; fallback: 100; live: false }
                            RowLayout {
                                spacing: 6
                                Repeater {
                                    model: [{v: 80, n: "Pequeno"}, {v: 100, n: "Normal"}, {v: 125, n: "Grande"}]
                                    delegate: Pill { required property var modelData; text: modelData.n; active: panel.num("uiScale", 100) === modelData.v; onClicked: panel.set("uiScale", modelData.v) }
                                }
                            }
                        }
                        Field {
                            label: "Espaço nos cartões"
                            Segmented {
                                options: [{value: "compact", text: "Compacto"}, {value: "normal", text: "Normal"}, {value: "comfortable", text: "Confortável"}]
                                value: panel.cfg.density || "normal"
                                onPicked: v => panel.set("density", v)
                            }
                        }
                        Field { label: "Tamanho dos ícones"; Slide { key: "iconScale"; from: 60; to: 160; step: 5; fallback: 100 } }
                        Field {
                            label: "Cor de destaque"
                            Flow {
                                Layout.fillWidth: true; spacing: 8
                                Repeater {
                                    model: panel.accentColors
                                    delegate: Rectangle {
                                        required property string modelData
                                        readonly property bool current: (panel.cfg.accentColor || "#3daee9").toLowerCase() === modelData
                                        width: 26; height: 26; radius: 13; color: modelData
                                        border.width: current ? 3 : 0; border.color: panel.t.ink
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: panel.set("accentColor", modelData) }
                                        Accessible.role: Accessible.RadioButton
                                        Accessible.name: modelData
                                        Accessible.checked: current
                                    }
                                }
                            }
                        }
                        Field { label: "Opacidade do fundo"; Slide { key: "backgroundOpacity"; from: 60; to: 100; step: 1; fallback: 94 } }
                        Toggle { text: "Animações"; hint: "Ícones do clima e transições"; on: panel.cfg.animations !== false; onToggled: panel.set("animations", !on) }
                    }

                    // ── Cartões ───────────────────────────────────────────
                    ColumnLayout {
                        visible: panel.section === "cards"
                        Layout.fillWidth: true; spacing: 4
                        Text {
                            text: "Ligue o que quer ver. Um cartão ligado entra na coluna com menos cartões; para mudar de lugar, use ✎ Editar."
                            color: panel.t.muted; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true; Layout.bottomMargin: 6
                        }
                        Repeater {
                            model: panel.host.allIds.filter(id => id !== "chat")
                            delegate: Toggle {
                                required property string modelData
                                text: panel.host.names[modelData] || modelData
                                // Cartões que dependem dos controles do sistema não existem na prévia.
                                enabled: panel.available(modelData)
                                on: panel.cardShown(modelData)
                                onToggled: panel.setCard(modelData, !on)
                            }
                        }
                    }

                    // ── Ações rápidas ─────────────────────────────────────
                    ColumnLayout {
                        id: quickPage
                        visible: panel.section === "quick"
                        Layout.fillWidth: true; spacing: 4
                        readonly property var order: QI.enabled(panel.cfg.quickItems || "")
                        Text {
                            text: "Escolha os botões do cartão Ações rápidas e a ordem deles."
                            color: panel.t.muted; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true; Layout.bottomMargin: 6
                        }
                        Repeater {
                            // Ligados na ordem escolhida, depois os desligados.
                            model: quickPage.order.map(id => QI.info(id)).concat(QI.all.filter(x => quickPage.order.indexOf(x.id) < 0))
                            delegate: RowLayout {
                                id: qrow
                                required property var modelData
                                readonly property int pos: quickPage.order.indexOf(modelData.id)
                                Layout.fillWidth: true; spacing: 4
                                Toggle {
                                    Layout.fillWidth: true
                                    icon: qrow.modelData.icon
                                    text: qrow.modelData.text
                                    hint: qrow.modelData.kind === "toggle" ? "Liga e desliga" : qrow.modelData.kind === "profile" ? "Economia, equilibrado ou desempenho" : "Botão de sessão"
                                    on: qrow.pos >= 0
                                    onToggled: panel.set("quickItems", QI.toggled(panel.cfg.quickItems || "", qrow.modelData.id))
                                }
                                IconButton { t: panel.t; icon: "arrow-up"; size: 24; tip: "Subir"; enabled: qrow.pos > 0; onClicked: panel.set("quickItems", QI.moved(panel.cfg.quickItems || "", qrow.modelData.id, -1)) }
                                IconButton { t: panel.t; icon: "arrow-down"; size: 24; tip: "Descer"; enabled: qrow.pos >= 0 && qrow.pos < quickPage.order.length - 1; onClicked: panel.set("quickItems", QI.moved(panel.cfg.quickItems || "", qrow.modelData.id, 1)) }
                            }
                        }
                        RowLayout {
                            Layout.topMargin: 6; spacing: 6
                            Pill { text: "Restaurar padrão"; onClicked: panel.set("quickItems", "") }
                            Pill {
                                visible: !panel.cardShown("quick")
                                text: "Mostrar o cartão"; active: true
                                onClicked: panel.setCard("quick", true)
                            }
                        }
                    }

                    // ── Barra lateral ─────────────────────────────────────
                    ColumnLayout {
                        visible: panel.section === "sidebar"
                        Layout.fillWidth: true; spacing: 12
                        Text {
                            text: "Além do widget, o Plasdria pode ficar numa barra na borda da tela, como um app: horário, clima, CPU, bateria, conexão, música e ações rápidas sempre à vista. Um toque no logo abre o Plasdria completo."
                            color: panel.t.muted; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true
                        }
                        Field {
                            label: panel.sidebarState === "pinned" || panel.sidebarState === "autohide" ? "Onde fica" : "Criar"
                            hint: "Nas laterais ela vira uma coluna; em cima e embaixo, uma linha. Escolher outra borda move a barra."
                            Flow {
                                Layout.fillWidth: true; spacing: 6
                                Repeater {
                                    model: [{id: "right", text: "Direita"}, {id: "left", text: "Esquerda"}, {id: "top", text: "Em cima"}, {id: "bottom", text: "Embaixo"}]
                                    delegate: Pill {
                                        required property var modelData
                                        readonly property bool busy: panel.busyEdges.indexOf(modelData.id) >= 0
                                        text: modelData.text + (busy ? " (ocupada)" : "")
                                        // A borda atual fica destacada; as que já têm outro painel ficam apagadas.
                                        solid: panel.sidebarState !== "none" && panel.sidebarState !== "" && panel.sidebarEdge === modelData.id
                                        active: !solid
                                        enabled: !!panel.host.sys && !busy
                                        opacity: enabled ? 1 : 0.45
                                        onClicked: panel.placeBar(modelData.id)
                                    }
                                }
                                Pill { text: "Remover"; enabled: !!panel.host.sys && panel.sidebarState !== "none"; onClicked: panel.host.sys.removeSidebars() }
                            }
                            Text { visible: panel.sidebarStatus !== ""; text: panel.sidebarStatus; color: panel.t.accent; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        }
                        Field {
                            label: "Minimizar"
                            hint: panel.sidebarState === "none" ? "Crie a barra primeiro." : "Também dá para minimizar e fixar pelo botão no topo da própria barra."
                            Toggle {
                                icon: "sidebar-collapse-right"
                                text: "Esconder a barra quando não estiver usando"
                                hint: "Ela volta ao encostar o mouse na borda da tela"
                                enabled: panel.sidebarState === "pinned" || panel.sidebarState === "autohide"
                                on: panel.sidebarState === "autohide"
                                onToggled: panel.host.sys.setSidebarAutoHide(!on)
                            }
                        }
                        Field {
                            label: "O que aparece"
                            hint: "Cada cópia do Plasdria guarda a sua escolha: mude aqui antes de criar, ou pelo ⚙ do Plasdria aberto na própria barra."
                            Repeater {
                                model: panel.sidebarParts
                                delegate: Toggle {
                                    required property var modelData
                                    icon: modelData.icon; text: modelData.text
                                    on: panel.sidebarHidden.indexOf(modelData.id) < 0
                                    onToggled: panel.toggleSidebarPart(modelData.id)
                                }
                            }
                        }
                    }

                    // ── Geral ─────────────────────────────────────────────
                    ColumnLayout {
                        visible: panel.section === "general"
                        Layout.fillWidth: true; spacing: 14
                        Field {
                            label: "Seu nome"
                            hint: "Usado na saudação."
                            B.TextField {
                                id: nameField
                                Layout.fillWidth: true
                                text: panel.cfg.userName || ""
                                placeholderText: "Como quer ser chamado?"; placeholderTextColor: panel.t.faint
                                color: panel.t.ink; font.pixelSize: 12
                                leftPadding: 10; topPadding: 6; bottomPadding: 6
                                background: Rectangle { radius: 8; color: panel.t.cardRaised; border.color: nameField.activeFocus ? panel.t.accentLine : "transparent" }
                                onEditingFinished: panel.set("userName", text.trim())
                            }
                        }
                        Field {
                            label: "IA padrão"
                            hint: "A IA usada ao abrir o widget. Modelos e chaves ficam em Mais opções."
                            SelectPill {
                                t: panel.t; Layout.preferredWidth: 180
                                options: panel.providers
                                value: panel.cfg.defaultProvider || "antigravity"
                                onPicked: v => panel.set("defaultProvider", v)
                            }
                        }
                        Field {
                            label: "Resumo do dia"
                            Toggle { text: "Notificação diária com o resumo"; on: panel.cfg.summaryEnabled !== false; onToggled: panel.set("summaryEnabled", !on) }
                            RowLayout {
                                visible: panel.cfg.summaryEnabled !== false
                                spacing: 8
                                Text { text: "A partir das"; color: panel.t.muted; font.pixelSize: 12 }
                                SelectPill {
                                    t: panel.t; Layout.preferredWidth: 80
                                    options: [5, 6, 7, 8, 9, 10, 11, 12].map(h => ({value: String(h), text: h + " h"}))
                                    value: String(panel.num("summaryHour", 8))
                                    onPicked: v => panel.set("summaryHour", Number(v))
                                }
                            }
                        }
                        Field {
                            label: "Agenda"
                            RowLayout {
                                spacing: 8
                                Text { text: "Avisar antes dos eventos"; color: panel.t.ink; font.pixelSize: 12 }
                                SelectPill {
                                    t: panel.t; Layout.preferredWidth: 110
                                    options: [0, 5, 10, 15, 30, 60].map(m => ({value: String(m), text: m === 0 ? "Não avisar" : m + " min"}))
                                    value: String(panel.num("eventLeadMinutes", 10))
                                    onPicked: v => panel.set("eventLeadMinutes", Number(v))
                                }
                            }
                        }
                        Field {
                            label: "Alertas do sistema"
                            Toggle { text: "Bateria baixa, disco cheio, CPU quente e internet fora"; on: panel.cfg.alertsEnabled !== false; onToggled: panel.set("alertsEnabled", !on) }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: panel.t.border }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Text {
                    text: "Cidade, agenda iCal, modelos, chaves e limites dos alertas ficam em Mais opções."
                    color: panel.t.faint; font.pixelSize: 10; wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                Pill { text: "Mais opções…"; onClicked: panel.moreRequested() }
                Pill { text: "Concluir"; solid: true; onClicked: panel.closeRequested() }
            }
        }
    }

    // ── Peças ────────────────────────────────────────────────────────────
    component Field: ColumnLayout {
        id: field
        property string label
        property string hint
        default property alias content: fieldBody.data
        Layout.fillWidth: true; spacing: 6
        Text { text: field.label; color: panel.t.muted; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.6; font.capitalization: Font.AllUppercase }
        ColumnLayout { id: fieldBody; Layout.fillWidth: true; spacing: 6 }
        Text { visible: field.hint !== ""; text: field.hint; color: panel.t.faint; font.pixelSize: 10; wrapMode: Text.Wrap; Layout.fillWidth: true }
    }

    component Pill: Rectangle {
        id: pill
        property string text
        property bool solid: false
        property bool active: false
        signal clicked()
        implicitHeight: 28; implicitWidth: pillText.implicitWidth + 24; radius: 14
        color: solid ? panel.t.accent : active ? panel.t.accentSoft : pillHover.hovered ? panel.t.cardRaised : "transparent"
        border.color: solid ? "transparent" : active ? panel.t.accentLine : panel.t.border
        Text { id: pillText; anchors.centerIn: parent; text: pill.text; font.pixelSize: 11; font.weight: Font.DemiBold
            color: pill.solid ? panel.t.textOnAccent : pill.active ? panel.t.accent : panel.t.ink }
        HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pill.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: text
    }

    component Segmented: Rectangle {
        id: seg
        property var options: []
        property string value
        signal picked(string value)
        Layout.fillWidth: true; implicitHeight: 32; radius: 16
        color: panel.t.tint; border.color: panel.t.border
        RowLayout {
            anchors.fill: parent; anchors.margins: 3; spacing: 2
            Repeater {
                model: seg.options
                delegate: Rectangle {
                    id: opt
                    required property var modelData
                    readonly property bool current: seg.value === modelData.value
                    Layout.fillWidth: true; Layout.fillHeight: true; radius: 13
                    color: current ? panel.t.accentSoft : optHover.hovered ? panel.t.cardRaised : "transparent"
                    border.color: current ? panel.t.accentLine : "transparent"
                    Text { anchors.centerIn: parent; text: opt.modelData.text; font.pixelSize: 12; color: opt.current ? panel.t.accent : panel.t.ink; font.weight: opt.current ? Font.DemiBold : Font.Normal }
                    HoverHandler { id: optHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: seg.picked(opt.modelData.value) }
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData.text
                    Accessible.checked: current
                }
            }
        }
    }

    // Barra para números da configuração. live: false só grava ao soltar (o tamanho geral redesenha tudo).
    component Slide: RowLayout {
        id: slide
        property string key
        property real from: 0
        property real to: 100
        property real step: 1
        property real fallback: 0
        property bool live: true
        property real pending: -1
        readonly property real current: pending >= 0 ? pending : panel.num(key, fallback)
        Layout.fillWidth: true; spacing: 10
        LevelBar {
            t: panel.t; Layout.fillWidth: true
            value: (slide.current - slide.from) / (slide.to - slide.from)
            onMoved: v => {
                const n = Math.round((slide.from + v * (slide.to - slide.from)) / slide.step) * slide.step
                if (slide.live) panel.set(slide.key, n); else slide.pending = n
            }
            onReleased: { if (!slide.live && slide.pending >= 0) panel.set(slide.key, slide.pending); slide.pending = -1 }
        }
        Text { text: Math.round(slide.current) + "%"; color: panel.t.muted; font.pixelSize: 11; Layout.preferredWidth: 38; horizontalAlignment: Text.AlignRight }
    }

    component Toggle: Rectangle {
        id: tg
        property string text
        property string hint
        property string icon
        property bool on: false
        signal toggled()
        Layout.fillWidth: true; implicitHeight: Math.max(36, tgCol.implicitHeight + 12); radius: 9
        color: tgHover.hovered && enabled ? panel.t.cardRaised : "transparent"
        opacity: enabled ? 1 : 0.45
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 10
            Kirigami.Icon { visible: tg.icon !== ""; source: tg.icon; implicitWidth: 16; implicitHeight: 16; isMask: true; color: tg.on ? panel.t.accent : panel.t.muted }
            ColumnLayout {
                id: tgCol
                spacing: 1; Layout.fillWidth: true
                Text { text: tg.text; color: panel.t.ink; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
                Text { visible: tg.hint !== ""; text: tg.hint; color: panel.t.faint; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
            }
            Rectangle {   // interruptor
                implicitWidth: 34; implicitHeight: 18; radius: 9
                color: tg.on ? panel.t.accent : panel.t.border
                Behavior on color { ColorAnimation { duration: panel.t.duration } }
                Rectangle {
                    width: 14; height: 14; radius: 7; y: 2
                    x: tg.on ? parent.width - width - 2 : 2
                    color: tg.on ? panel.t.textOnAccent : panel.t.ink
                    Behavior on x { NumberAnimation { duration: panel.t.duration } }
                }
            }
        }
        HoverHandler { id: tgHover; cursorShape: tg.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: tg.enabled; onTapped: tg.toggled() }
        Accessible.role: Accessible.CheckBox
        Accessible.name: text
        Accessible.checked: on
    }
}
