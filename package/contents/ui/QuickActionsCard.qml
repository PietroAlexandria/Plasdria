import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as B
import org.kde.kirigami as Kirigami
import "quickitems.js" as QI

// Ações rápidas: Não perturbe, luz noturna, manter acordado, Wi-Fi, perfil de energia e sessão.
Card {
    id: card
    required property var sys
    // Ids ligados, na ordem escolhida (JSON). Vazio = todos.
    property string items: ""
    readonly property var order: QI.enabled(items)
    function rank(id) { return order.indexOf(id) }
    title: "Ações rápidas"
    icon: "configure-shortcuts"
    Component.onCompleted: sys.acquire("quick")
    Component.onDestruction: sys.release("quick")

    readonly property var q: sys.quick || ({})
    readonly property var profileNames: ({"power-saver": "Economia", "balanced": "Equilibrado", "performance": "Desempenho"})
    readonly property var profileIcons: ({"power-saver": "battery-profile-powersave-symbolic", "balanced": "battery-profile-balanced-symbolic", "performance": "battery-profile-performance-symbolic"})

    // Liga e desliga: o que não existe neste computador não aparece.
    readonly property var toggles: [
        {id: "dnd", visible: !!q.dndAvailable, on: !!q.dnd || !!q.dndOther,
         icon: "notifications-disabled-symbolic", text: "Não perturbe",
         state: q.dnd ? "Ligado" : q.dndOther ? "Ligado por outro app" : "Desligado",
         tip: "Esconde as notificações (as urgentes ainda aparecem)"},
        {id: "night", visible: !!q.nightAvailable, on: !!q.night,
         icon: "redshift-status-on", text: "Luz noturna",
         state: !q.nightEnabled ? "Configurar…" : q.night ? "Ligada" : q.nightOther ? "Pausada por outro app" : "Pausada",
         tip: q.nightEnabled ? "Pausa ou retoma a luz noturna do Plasma" : "A luz noturna está desligada nas Configurações do sistema"},
        {id: "caffeine", visible: true, on: !!q.caffeine,
         icon: q.caffeine ? "system-suspend-inhibited" : "system-suspend-uninhibited", text: "Manter acordado",
         state: q.caffeine ? "Tela não apaga" : "Desligado",
         tip: "Impede que a tela apague, bloqueie ou que o computador suspenda"},
        {id: "wifi", visible: !!q.wifiAvailable, on: !!q.wifi,
         icon: q.wifi ? "network-wireless-symbolic" : "network-wireless-disconnected-symbolic", text: "Wi-Fi",
         state: q.wifi ? "Ligado" : "Desligado", tip: q.wifi ? "Desligar o Wi-Fi" : "Ligar o Wi-Fi"}
    ].filter(x => x.visible && card.rank(x.id) >= 0).sort((a, b) => card.rank(a.id) - card.rank(b.id))

    readonly property bool showProfile: rank("profile") >= 0 && (q.profiles || []).length > 1
    readonly property var actionItems: [
        {id: "lock", icon: "system-lock-screen-symbolic", text: "Bloquear", visible: true},
        {id: "suspend", icon: "system-suspend-symbolic", text: "Suspender", visible: !!q.canSuspend},
        {id: "shot", icon: "camera-photo-symbolic", text: "Captura", visible: true},
        {id: "session", icon: "system-shutdown-symbolic", text: "Desligar…", visible: true}
    ].filter(x => x.visible && card.rank(x.id) >= 0).sort((a, b) => card.rank(a.id) - card.rank(b.id))

    Text {
        visible: card.toggles.length === 0 && !card.showProfile && card.actionItems.length === 0
        text: "Nenhuma ação escolhida. Escolha quais aparecem nas configurações do widget (⚙)."
        color: card.t.faint; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
    }

    function toggle(id) {
        switch (id) {
        case "dnd": sys.setDoNotDisturb(!q.dnd); break
        case "night": if (!q.nightEnabled) sys.launch("app:kcm_nightlight"); else sys.setNightLight(!q.night); break
        case "caffeine": sys.setCaffeine(!q.caffeine); break
        case "wifi": sys.setWifi(!q.wifi); break
        }
    }

    GridLayout {
        visible: card.toggles.length > 0
        Layout.fillWidth: true
        columns: Math.max(1, Math.min(card.toggles.length, Math.floor((card.width - card.padding * 2 + 8) / 128)))
        columnSpacing: 8; rowSpacing: 8
        Repeater {
            model: card.toggles
            delegate: Rectangle {
                id: tile
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: tileRow.implicitHeight + 16
                radius: 10
                color: modelData.on ? card.t.accentSoft : tileHover.hovered ? card.t.cardRaised : card.t.tint
                border.color: modelData.on ? card.t.accentLine : card.t.border
                Behavior on color { ColorAnimation { duration: card.t.duration } }
                RowLayout {
                    id: tileRow
                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8
                    spacing: 8
                    Kirigami.Icon {
                        source: tile.modelData.icon
                        implicitWidth: Math.round(18 * card.t.iconScale); implicitHeight: implicitWidth
                        isMask: true; color: tile.modelData.on ? card.t.accent : card.t.muted
                    }
                    ColumnLayout {
                        spacing: 0; Layout.fillWidth: true
                        Text { text: tile.modelData.text; color: card.t.ink; font.pixelSize: 12; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: tile.modelData.state; color: tile.modelData.on ? card.t.accent : card.t.faint; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                }
                HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: card.toggle(tile.modelData.id) }
                B.ToolTip.visible: tileHover.hovered
                B.ToolTip.text: modelData.tip
                B.ToolTip.delay: 600
                Accessible.role: Accessible.CheckBox
                Accessible.name: modelData.text
                Accessible.checked: modelData.on
            }
        }
    }

    // Perfil de energia (power-profiles-daemon)
    RowLayout {
        visible: card.showProfile
        Layout.fillWidth: true; spacing: 8
        Text { text: "Energia"; color: card.t.muted; font.pixelSize: 11; Layout.preferredWidth: implicitWidth }
        Rectangle {
            Layout.fillWidth: true; implicitHeight: 30; radius: 15
            color: card.t.tint; border.color: card.t.border
            RowLayout {
                anchors.fill: parent; anchors.margins: 3; spacing: 2
                Repeater {
                    model: card.q.profiles || []
                    delegate: Rectangle {
                        id: seg
                        required property string modelData
                        readonly property bool current: card.q.profile === modelData
                        Layout.fillWidth: true; Layout.fillHeight: true; radius: 12
                        color: current ? card.t.accentSoft : segHover.hovered ? card.t.cardRaised : "transparent"
                        border.color: current ? card.t.accentLine : "transparent"
                        Behavior on color { ColorAnimation { duration: card.t.duration } }
                        RowLayout {
                            anchors.centerIn: parent; spacing: 5
                            Kirigami.Icon {
                                source: card.profileIcons[seg.modelData] || "battery-profile-balanced-symbolic"
                                implicitWidth: 14; implicitHeight: 14; isMask: true
                                color: seg.current ? card.t.accent : card.t.muted
                            }
                            Text {
                                visible: seg.width > 70
                                text: card.profileNames[seg.modelData] || seg.modelData
                                color: seg.current ? card.t.accent : card.t.ink
                                font.pixelSize: 11; font.weight: seg.current ? Font.DemiBold : Font.Normal
                            }
                        }
                        HoverHandler { id: segHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: card.sys.setPowerProfile(seg.modelData) }
                        B.ToolTip.visible: segHover.hovered && seg.width <= 70
                        B.ToolTip.text: card.profileNames[seg.modelData] || seg.modelData
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: card.profileNames[seg.modelData] || seg.modelData
                        Accessible.checked: seg.current
                    }
                }
            }
        }
    }

    Rectangle { visible: card.actionItems.length > 0 && (card.toggles.length > 0 || card.showProfile); Layout.fillWidth: true; height: 1; color: card.t.border }

    // Sessão
    RowLayout {
        visible: card.actionItems.length > 0
        Layout.fillWidth: true; spacing: 4
        Repeater {
            model: card.actionItems
            delegate: Rectangle {
                id: action
                required property var modelData
                Layout.fillWidth: true; implicitHeight: actionCol.implicitHeight + 12; radius: 9
                color: actionHover.hovered ? card.t.cardRaised : "transparent"
                ColumnLayout {
                    id: actionCol
                    anchors.centerIn: parent; spacing: 3
                    Kirigami.Icon {
                        source: action.modelData.icon; Layout.alignment: Qt.AlignHCenter
                        implicitWidth: Math.round(18 * card.t.iconScale); implicitHeight: implicitWidth
                        isMask: true; color: action.modelData.id === "session" && actionHover.hovered ? card.t.bad : card.t.ink
                    }
                    Text { text: action.modelData.text; color: card.t.muted; font.pixelSize: 10; Layout.alignment: Qt.AlignHCenter }
                }
                HoverHandler { id: actionHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        switch (action.modelData.id) {
                        case "lock": card.sys.lockScreen(); break
                        case "suspend": card.sys.suspend(); break
                        case "shot": card.sys.launch("app:org.kde.spectacle"); break
                        case "session": card.sys.sessionMenu(); break
                        }
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: modelData.text
            }
        }
    }
}
