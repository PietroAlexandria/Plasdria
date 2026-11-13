import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as B
import org.kde.kirigami as Kirigami
import "quickitems.js" as QI

// Barra do Plasdria num painel do Plasma, em qualquer borda: coluna nas laterais, linha em cima e embaixo.
// Mostra o essencial (horário, clima, uso do computador, bateria, conexão, música e ações rápidas)
// e abre o Plasdria completo com um toque.
Item {
    id: bar
    required property var t
    required property var dash
    required property var net
    required property var media
    required property var client
    required property var cfg
    property var sys: null
    property string edge: "right"   // borda da tela: left, right, top ou bottom
    readonly property bool horizontal: edge === "top" || edge === "bottom"
    readonly property bool minimized: !!sys && sys.sidebarState === "autohide"
    // Recolhida: o painel fica mais fino e a barra mostra só o essencial (sem textos de apoio).
    readonly property bool compact: horizontal ? height < 48 : width < 66
    readonly property var busyEdges: sys && sys.sidebarBusyEdges ? sys.sidebarBusyEdges : []
    property bool moving: false   // mostra as setas para escolher outra borda
    readonly property var edgeChoices: [
        {id: "top", icon: "go-up-symbolic", text: "Mover para cima", short: "Cima"},
        {id: "bottom", icon: "go-down-symbolic", text: "Mover para baixo", short: "Baixo"},
        {id: "left", icon: "go-previous-symbolic", text: "Mover para a esquerda", short: "Esquerda"},
        {id: "right", icon: "go-next-symbolic", text: "Mover para a direita", short: "Direita"}]
    function moveTo(id) { moving = false; if (id !== edge && sys) sys.createSidebar(id, {}) }
    signal openRequested()
    signal chatRequested()

    // Seções que você escolheu esconder em ⚙ → Barra lateral.
    readonly property var hidden: { try { const l = JSON.parse(cfg.sidebarHidden || "[]"); return Array.isArray(l) ? l : [] } catch (e) { return [] } }
    function shown(id) { return hidden.indexOf(id) < 0 }

    // Tudo escala com a espessura do painel (largura nas laterais, altura em cima/embaixo).
    readonly property real thickness: horizontal ? height : width
    readonly property real unit: horizontal ? Math.max(0.55, Math.min(1.3, height / 60)) : Math.max(0.6, Math.min(1.4, width / 80))
    readonly property var q: sys ? (sys.quick || ({})) : ({})
    readonly property var quickToggles: !sys ? [] : QI.enabled(cfg.quickItems || "").filter(id => {
        if (id === "dnd") return !!q.dndAvailable
        if (id === "night") return !!q.nightAvailable
        if (id === "wifi") return !!q.wifiAvailable
        if (id === "suspend") return !!q.canSuspend
        return id !== "profile"
    })
    Component.onCompleted: if (sys) { sys.acquire("quick"); sys.refreshSidebar() }
    Component.onDestruction: if (sys) sys.release("quick")

    Layout.fillHeight: true
    Layout.fillWidth: true
    Layout.minimumWidth: horizontal ? 200 : 48
    Layout.minimumHeight: horizontal ? 36 : 200
    Layout.preferredWidth: horizontal ? column.implicitWidth + (chatButton.visible ? chatButton.width + 24 : 16) : 84
    Layout.preferredHeight: horizontal ? 56 : -1

    // Ao reaparecer (mouse na borda), confere se a barra foi minimizada ou fixada por outro lugar.
    HoverHandler { onHoveredChanged: if (hovered && bar.sys) bar.sys.refreshSidebar() }

    Rectangle {
        anchors.fill: parent; anchors.margins: 3
        radius: Math.min(18, bar.thickness / 3)
        color: bar.t.background; border.color: bar.t.border
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.topMargin: bar.horizontal ? 3 : 10
        anchors.bottomMargin: bar.horizontal ? 3 : (chatButton.visible ? chatButton.height + 22 : 10)
        anchors.leftMargin: bar.horizontal ? 10 : 0
        anchors.rightMargin: bar.horizontal ? (chatButton.visible ? chatButton.width + 22 : 10) : 0
        contentWidth: bar.horizontal ? column.implicitWidth : width
        contentHeight: bar.horizontal ? height : column.implicitHeight
        flickableDirection: bar.horizontal ? Flickable.HorizontalFlick : Flickable.VerticalFlick
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: bar.horizontal ? contentWidth > width : contentHeight > height

        GridLayout {
            id: column
            width: bar.horizontal ? implicitWidth : flick.width
            height: bar.horizontal ? flick.height : implicitHeight
            flow: bar.horizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
            rows: bar.horizontal ? 1 : 99
            columns: bar.horizontal ? 99 : 1
            rowSpacing: Math.round(10 * bar.unit)
            columnSpacing: Math.round(10 * bar.unit)

            // Controles da barra: minimizar/fixar, expandir/recolher e mover para outra borda.
            GridLayout {
                visible: !!bar.sys
                Layout.alignment: Qt.AlignCenter
                // Na coluna expandida os três cabem lado a lado; recolhida, um embaixo do outro.
                flow: bar.horizontal || !bar.compact ? GridLayout.LeftToRight : GridLayout.TopToBottom
                rows: bar.horizontal || !bar.compact ? 1 : 3
                columns: bar.horizontal || !bar.compact ? 3 : 1
                rowSpacing: 2; columnSpacing: 2
                IconButton {
                    t: bar.t; size: Math.max(24, Math.round(22 * bar.unit))
                    icon: bar.minimized ? "window-pin" : ({left: "sidebar-collapse-left", right: "sidebar-collapse-right", top: "go-up-symbolic", bottom: "go-down-symbolic"})[bar.edge] || "sidebar-collapse-right"
                    active: bar.minimized
                    tip: bar.minimized ? "Fixar a barra (sempre à vista)" : "Minimizar: a barra se esconde e volta ao encostar o mouse na borda"
                    onClicked: bar.sys.setSidebarAutoHide(!bar.minimized)
                }
                IconButton {
                    t: bar.t; size: Math.max(24, Math.round(22 * bar.unit))
                    icon: bar.compact ? "zoom-in-symbolic" : "zoom-out-symbolic"
                    tip: bar.compact ? "Expandir: barra maior, com mais detalhes" : "Recolher: barra mais fina, só o essencial"
                    onClicked: bar.sys.setSidebarCompact(!bar.compact)
                }
                IconButton {
                    t: bar.t; size: Math.max(24, Math.round(22 * bar.unit))
                    icon: bar.moving ? "window-close" : "transform-move"
                    active: bar.moving
                    tip: bar.moving ? "Cancelar" : "Mover a barra para outra borda da tela"
                    onClicked: { bar.moving = !bar.moving; if (bar.moving) bar.sys.refreshSidebar() }
                }
            }

            // Escolha da borda (aparece ao tocar em Mover): botões grandes com nome, fáceis de acertar.
            // Bordas com outro painel ficam apagadas.
            GridLayout {
                visible: bar.moving
                Layout.alignment: Qt.AlignCenter
                Layout.fillWidth: !bar.horizontal
                Layout.leftMargin: bar.horizontal ? 0 : 5; Layout.rightMargin: bar.horizontal ? 0 : 5
                columns: bar.horizontal ? 4 : 1
                rowSpacing: 4; columnSpacing: 4
                Repeater {
                    model: bar.edgeChoices
                    delegate: Rectangle {
                        id: choice
                        required property var modelData
                        readonly property bool here: bar.edge === modelData.id
                        readonly property bool busy: bar.busyEdges.indexOf(modelData.id) >= 0
                        readonly property bool usable: !here && !busy
                        Layout.fillWidth: !bar.horizontal
                        implicitWidth: bar.horizontal ? choiceRow.implicitWidth + 20 : 0
                        implicitHeight: bar.horizontal ? Math.max(30, bar.height - 16) : 34
                        radius: 9
                        color: here ? bar.t.accentSoft : choiceHover.hovered && usable ? bar.t.accent : bar.t.cardRaised
                        border.color: here ? bar.t.accentLine : "transparent"
                        opacity: busy ? 0.4 : 1
                        RowLayout {
                            id: choiceRow
                            anchors.centerIn: parent; spacing: bar.horizontal ? 6 : 3
                            Kirigami.Icon {
                                source: choice.modelData.icon
                                implicitWidth: bar.horizontal ? 18 : 16; implicitHeight: implicitWidth; isMask: true
                                color: choiceHover.hovered && choice.usable ? bar.t.textOnAccent : choice.here ? bar.t.accent : bar.t.ink
                            }
                            Text {
                                // Na coluna recolhida só cabe o ícone.
                                visible: bar.horizontal || !bar.compact
                                text: choice.modelData.short
                                color: choiceHover.hovered && choice.usable ? bar.t.textOnAccent : choice.here ? bar.t.accent : bar.t.ink
                                font.pixelSize: bar.horizontal ? 11 : 10; font.weight: Font.DemiBold
                            }
                        }
                        HoverHandler { id: choiceHover; cursorShape: choice.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler { enabled: choice.usable; onTapped: bar.moveTo(choice.modelData.id) }
                        B.ToolTip.visible: choiceHover.hovered
                        B.ToolTip.text: choice.here ? "A barra já está aqui" : choice.busy ? "Ocupado: já tem outro painel nessa borda" : choice.modelData.text
                        B.ToolTip.delay: 300
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.text
                    }
                }
            }

            // Abre o Plasdria completo
            Tile {
                tip: "Abrir o Plasdria"; clickable: true
                onTapped: bar.openRequested()
                Image { source: "assets/icon.png"; Layout.alignment: Qt.AlignCenter; Layout.preferredWidth: Math.round(30 * bar.unit); Layout.preferredHeight: Layout.preferredWidth; sourceSize: Qt.size(64, 64); smooth: true; mipmap: true }
            }

            // Horário
            Tile {
                visible: bar.shown("clock")
                tip: bar.dash.localDate || ""
                Text { text: (bar.dash.localTime || "--:--").slice(0, 5); color: bar.t.ink; font.pixelSize: Math.round(19 * bar.unit); font.weight: Font.DemiBold; Layout.alignment: Qt.AlignHCenter }
                Text { visible: !bar.compact; text: bar.shortDate(); color: bar.t.muted; font.pixelSize: Math.round(10 * bar.unit); Layout.alignment: Qt.AlignHCenter }
            }

            // Clima
            Tile {
                visible: bar.shown("weather") && (bar.dash.weatherTemperature || "") !== ""
                row: bar.horizontal
                tip: (bar.dash.weatherLocation || "") + (bar.dash.weatherSummary ? " · " + bar.dash.weatherSummary : "")
                Item {
                    Layout.alignment: Qt.AlignCenter; Layout.preferredWidth: Math.round(30 * bar.unit); Layout.preferredHeight: Math.round(24 * bar.unit)
                    WeatherIcon { t: bar.t; anchors.centerIn: parent; scale: 0.75 * bar.unit; code: bar.dash.forecast.length ? bar.dash.forecast[0].code : 0; animated: false }
                }
                Text { text: bar.dash.weatherTemperature || ""; color: bar.t.ink; font.pixelSize: Math.round(13 * bar.unit); Layout.alignment: Qt.AlignCenter }
            }

            Sep { visible: bar.shown("system") || bar.shown("battery") || bar.shown("network") }

            // Uso do computador
            Tile {
                visible: bar.shown("system")
                row: bar.horizontal
                tip: "CPU " + Math.round(bar.dash.cpuUsage) + "% · RAM " + Math.round(bar.dash.memoryUsage) + "% · toque para ver mais"
                clickable: true
                onTapped: bar.openRequested()
                Gauge { value: bar.dash.cpuUsage; label: "CPU" }
                Gauge { value: bar.dash.memoryUsage; label: "RAM" }
            }

            // Bateria
            Tile {
                visible: bar.shown("battery") && bar.dash.batteryPercent >= 0
                tip: (bar.dash.systemDetails.batteryState || "Bateria") + (bar.dash.systemDetails.batteryTime ? " · " + bar.dash.systemDetails.batteryTime : "")
                Kirigami.Icon {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: Math.round(20 * bar.unit); implicitHeight: implicitWidth; isMask: true
                    source: "battery-" + bar.batteryLevel() + (bar.dash.systemDetails.batteryState === "Carregando" ? "-charging" : "") + "-symbolic"
                    fallback: "battery-060-symbolic"
                    color: bar.t.levelColor(bar.dash.batteryPercent)
                }
                Text { text: Math.round(bar.dash.batteryPercent) + "%"; color: bar.t.ink; font.pixelSize: Math.round(12 * bar.unit); Layout.alignment: Qt.AlignHCenter }
            }

            // Conexão
            Tile {
                visible: bar.shown("network")
                tip: bar.net.online ? (bar.net.connectionName || "Conectado") + " · " + bar.net.latency + " ms" : "Sem internet"
                Kirigami.Icon {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: Math.round(20 * bar.unit); implicitHeight: implicitWidth; isMask: true
                    source: bar.net.online ? "network-wireless-symbolic" : "network-wireless-disconnected-symbolic"
                    color: bar.net.online ? bar.t.ink : bar.t.bad
                }
                Text {
                    visible: !bar.compact
                    text: bar.net.online ? (bar.net.latency > 0 ? bar.net.latency + " ms" : "on-line") : "off-line"
                    color: !bar.net.online ? bar.t.bad : bar.net.latency > 150 ? bar.t.warn : bar.t.muted
                    font.pixelSize: Math.round(10 * bar.unit); Layout.alignment: Qt.AlignHCenter
                }
            }

            // Música
            Sep { visible: bar.shown("media") && bar.media.available }
            Tile {
                visible: bar.shown("media") && bar.media.available
                row: bar.horizontal
                tip: (bar.media.title || "") + (bar.media.artist ? " — " + bar.media.artist : "")
                IconButton { t: bar.t; Layout.alignment: Qt.AlignCenter; size: Math.round(32 * bar.unit); primary: true; icon: bar.media.playing ? "media-playback-pause" : "media-playback-start"; tip: bar.media.playing ? "Pausar" : "Tocar"; onClicked: bar.media.playPause() }
                Text {
                    visible: !bar.compact
                    text: bar.media.title || ""; color: bar.horizontal ? bar.t.ink : bar.t.muted
                    font.pixelSize: Math.round((bar.horizontal ? 11 : 9) * bar.unit); elide: Text.ElideRight
                    horizontalAlignment: bar.horizontal ? Text.AlignLeft : Text.AlignHCenter
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: !bar.horizontal; Layout.preferredWidth: bar.horizontal ? Math.round(130 * bar.unit) : -1
                    Layout.leftMargin: 4; Layout.rightMargin: 4
                }
            }

            // Ações rápidas
            Sep { visible: bar.shown("quick") && bar.quickToggles.length > 0 }
            GridLayout {
                visible: bar.shown("quick") && bar.quickToggles.length > 0
                Layout.alignment: Qt.AlignCenter
                columns: bar.horizontal ? 99 : bar.width >= 76 ? 2 : 1
                columnSpacing: 4; rowSpacing: 4
                Repeater {
                    model: bar.quickToggles
                    delegate: IconButton {
                        required property string modelData
                        t: bar.t; size: Math.round(30 * bar.unit)
                        icon: bar.quickIcon(modelData)
                        active: bar.quickOn(modelData)
                        tip: (QI.info(modelData) || {}).text || modelData
                        onClicked: bar.quickPress(modelData)
                    }
                }
            }
        }
    }

    // Conversar: abre o Plasdria já no campo do chat (no fim da barra).
    IconButton {
        id: chatButton
        visible: bar.shown("chat")
        x: bar.horizontal ? bar.width - width - 12 : (bar.width - width) / 2
        y: bar.horizontal ? (bar.height - height) / 2 : bar.height - height - 12
        t: bar.t; size: Math.round(34 * bar.unit); icon: "dialog-messages"
        tip: "Conversar com " + bar.client.providerName
        onClicked: bar.chatRequested()
    }

    function shortDate() {
        const stamp = dash.localTime   // atualiza junto com o relógio
        const d = new Date()
        return ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"][d.getDay()] + " " + d.getDate()
    }
    function batteryLevel() {
        const p = dash.batteryPercent
        const level = Math.max(0, Math.min(100, Math.round(p / 10) * 10))   // o Breeze tem ícones de 10 em 10
        return ("00" + level).slice(-3)
    }
    function quickIcon(id) {
        if (id === "caffeine") return q.caffeine ? "system-suspend-inhibited" : "system-suspend-uninhibited"
        if (id === "wifi") return q.wifi ? "network-wireless-symbolic" : "network-wireless-disconnected-symbolic"
        return (QI.info(id) || {}).icon || "configure"
    }
    function quickOn(id) {
        if (id === "dnd") return !!q.dnd || !!q.dndOther
        if (id === "night") return !!q.night
        if (id === "caffeine") return !!q.caffeine
        if (id === "wifi") return !!q.wifi
        return false
    }
    function quickPress(id) {
        switch (id) {
        case "dnd": sys.setDoNotDisturb(!q.dnd); break
        case "night": if (!q.nightEnabled) sys.launch("app:kcm_nightlight"); else sys.setNightLight(!q.night); break
        case "caffeine": sys.setCaffeine(!q.caffeine); break
        case "wifi": sys.setWifi(!q.wifi); break
        case "lock": sys.lockScreen(); break
        case "suspend": sys.suspend(); break
        case "shot": sys.launch("app:org.kde.spectacle"); break
        case "session": sys.sessionMenu(); break
        }
    }

    // ── Peças ────────────────────────────────────────────────────────────
    // Bloco da barra. row: conteúdo lado a lado (usado na barra horizontal), senão um embaixo do outro.
    component Tile: Rectangle {
        id: tile
        property string tip
        property bool clickable: false
        property bool row: false
        signal tapped()
        default property alias content: tileBody.data
        Layout.fillWidth: !bar.horizontal; Layout.fillHeight: bar.horizontal
        Layout.leftMargin: bar.horizontal ? 0 : 6; Layout.rightMargin: bar.horizontal ? 0 : 6
        Layout.topMargin: bar.horizontal ? 3 : 0; Layout.bottomMargin: bar.horizontal ? 3 : 0
        Layout.preferredWidth: bar.horizontal ? tileBody.implicitWidth + 12 : -1
        implicitHeight: tileBody.implicitHeight + 8
        radius: 10
        color: tileHover.hovered && clickable ? bar.t.cardRaised : "transparent"
        GridLayout {
            id: tileBody
            anchors.centerIn: parent
            width: bar.horizontal ? implicitWidth : parent.width
            flow: tile.row ? GridLayout.LeftToRight : GridLayout.TopToBottom
            rows: tile.row ? 1 : 99
            columns: tile.row ? 99 : 1
            rowSpacing: 2; columnSpacing: Math.round(6 * bar.unit)
        }
        HoverHandler { id: tileHover; cursorShape: tile.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: tile.clickable; onTapped: tile.tapped() }
        B.ToolTip.visible: tileHover.hovered && tip !== ""
        B.ToolTip.text: tip
        B.ToolTip.delay: 400
    }

    component Sep: Rectangle {
        Layout.alignment: Qt.AlignCenter
        Layout.preferredWidth: bar.horizontal ? 1 : bar.width * 0.4
        Layout.preferredHeight: bar.horizontal ? bar.height * 0.45 : 1
        color: bar.t.border
    }

    // Anel de uso. Na barra horizontal o nome vai só na dica, para caber na altura.
    component Gauge: Item {
        id: gauge
        property real value: 0
        property string label
        readonly property int ring: bar.horizontal ? Math.max(26, Math.round(bar.height - 18)) : Math.round(44 * bar.unit)
        Layout.alignment: Qt.AlignCenter
        Layout.preferredWidth: ring
        Layout.preferredHeight: bar.horizontal || bar.compact ? ring : ring + Math.round(12 * bar.unit)
        Ring {
            width: gauge.ring; height: gauge.ring
            value: gauge.value; label: Math.round(gauge.value) + "%"; caption: ""
            color: bar.t.usageColor(gauge.value); track: bar.t.border
            ink: bar.t.ink; mutedInk: bar.t.muted; duration: bar.t.animations ? 500 : 0
            thickness: Math.max(3, 4 * bar.unit)
        }
        Text { visible: !bar.horizontal && !bar.compact; anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; text: gauge.label; color: bar.t.faint; font.pixelSize: Math.round(9 * bar.unit) }
    }
}
