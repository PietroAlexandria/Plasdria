import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as B

// Cronômetro, timer e pomodoro. A lógica (e os alarmes) ficam no ClockEngine do main.qml.
Card {
    id: card
    required property var clock
    title: "Cronômetro e pomodoro"
    icon: "chronometer"
    // Aba do momento: fica no motor para sobreviver à recriação do cartão.
    readonly property string tab: clock.tab

    function pad(n) { return (n < 10 ? "0" : "") + n }
    // 83 400 ms -> "01:23" (ou "01:23.4" com décimos; "1:01:23" a partir de 1 h)
    function fmt(ms, tenths) {
        const total = Math.max(0, ms), s = Math.floor(total / 1000), h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), r = s % 60
        const base = (h > 0 ? h + ":" + pad(m) : pad(m)) + ":" + pad(r)
        return tenths ? base + "." + Math.floor(total % 1000 / 100) : base
    }
    readonly property var phaseNames: ({focus: "Foco", short: "Pausa curta", long: "Pausa longa"})

    component Button: Rectangle {
        id: button
        property string text
        property bool solid: false
        signal clicked()
        Layout.preferredHeight: 30; Layout.preferredWidth: Math.max(72, label.implicitWidth + 28); radius: 15
        color: solid ? (hover.hovered ? Qt.lighter(card.t.accent, 1.1) : card.t.accent) : (hover.hovered ? card.t.cardRaised : "transparent")
        border.color: solid ? "transparent" : card.t.border
        Text { id: label; anchors.centerIn: parent; text: button.text; font.pixelSize: 12; font.weight: Font.DemiBold; color: button.solid ? card.t.textOnAccent : card.t.muted }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: button.clicked() }
    }
    component Chip: Rectangle {
        id: chip
        property string text
        property bool active: false
        signal clicked()
        implicitHeight: 24; implicitWidth: chipLabel.implicitWidth + 18; radius: 12
        color: active ? card.t.accentSoft : (chipHover.hovered ? card.t.cardRaised : "transparent")
        border.color: active ? card.t.accentLine : card.t.border
        Text { id: chipLabel; anchors.centerIn: parent; text: chip.text; font.pixelSize: 11; font.weight: Font.DemiBold; color: chip.active ? card.t.accent : card.t.muted }
        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: chip.clicked() }
    }

    // Abas
    RowLayout {
        Layout.fillWidth: true; spacing: 6
        Repeater {
            model: [{id: "stopwatch", name: "Cronômetro"}, {id: "timer", name: "Timer"}, {id: "pomodoro", name: "Pomodoro"}]
            delegate: Chip { required property var modelData; text: modelData.name; active: card.tab === modelData.id; onClicked: card.clock.tab = modelData.id }
        }
        Item { Layout.fillWidth: true }
    }

    // ── Cronômetro ──
    ColumnLayout {
        visible: card.tab === "stopwatch"
        Layout.fillWidth: true; spacing: 8
        Text { text: card.fmt(card.clock.swElapsed(), true); color: card.t.ink; font.pixelSize: 38; font.weight: Font.Light; Layout.alignment: Qt.AlignHCenter }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: 8
            Button { text: card.clock.swRunning ? "Pausar" : (card.clock.swElapsed() > 0 ? "Continuar" : "Iniciar"); solid: true; onClicked: card.clock.swToggle() }
            Button { visible: card.clock.swRunning; text: "Volta"; onClicked: card.clock.swLap() }
            Button { visible: !card.clock.swRunning && card.clock.swElapsed() > 0; text: "Zerar"; onClicked: card.clock.swReset() }
        }
        Repeater {
            model: card.clock.laps.slice(0, 4)
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true; spacing: 8
                Text { text: "Volta " + modelData.n; color: card.t.faint; font.pixelSize: 11; Layout.preferredWidth: 60 }
                Text { text: card.fmt(modelData.total, true); color: card.t.ink; font.pixelSize: 11; Layout.fillWidth: true }
                Text { text: "+" + card.fmt(modelData.split, true); color: card.t.muted; font.pixelSize: 11 }
            }
        }
    }

    // ── Timer ──
    ColumnLayout {
        visible: card.tab === "timer"
        Layout.fillWidth: true; spacing: 8
        Item {
            Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 120; Layout.preferredHeight: 120
            Ring {
                anchors.fill: parent; thickness: 6; label: ""
                value: 100 * (1 - card.clock.tmRemaining() / Math.max(1, card.clock.tmTotal))
                color: card.clock.tmRunning ? card.t.accent : card.t.faint; track: card.t.border; ink: card.t.ink; mutedInk: card.t.muted; duration: 120
            }
            Text { anchors.centerIn: parent; text: card.fmt(card.clock.tmRemaining(), false); color: card.t.ink; font.pixelSize: 24; font.weight: Font.Light }
        }
        Flow {
            visible: !card.clock.tmRunning && !card.clock.tmPaused
            Layout.fillWidth: true; spacing: 6
            Repeater {
                model: [1, 5, 10, 15, 25, 45]
                delegate: Chip { required property int modelData; text: modelData + " min"; active: card.clock.tmTotal === modelData * 60000; onClicked: card.clock.tmSet(modelData) }
            }
            B.TextField {
                id: custom
                width: 74; height: 24
                placeholderText: "outro (min)"; placeholderTextColor: card.t.faint
                validator: IntValidator { bottom: 1; top: 600 }
                color: card.t.ink; font.pixelSize: 11; leftPadding: 8; topPadding: 2; bottomPadding: 2
                background: Rectangle { radius: 12; color: card.t.cardRaised; border.color: custom.activeFocus ? card.t.accentLine : "transparent" }
                onAccepted: { if (acceptableInput) card.clock.tmSet(parseInt(text)); text = "" }
            }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: 8
            Button { text: card.clock.tmRunning ? "Pausar" : (card.clock.tmPaused ? "Continuar" : "Iniciar"); solid: true; onClicked: card.clock.tmToggle() }
            Button { visible: card.clock.tmRunning || card.clock.tmPaused; text: "Zerar"; onClicked: card.clock.tmReset() }
        }
    }

    // ── Pomodoro ──
    ColumnLayout {
        visible: card.tab === "pomodoro"
        Layout.fillWidth: true; spacing: 8
        Item {
            Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 120; Layout.preferredHeight: 120
            Ring {
                anchors.fill: parent; thickness: 6; label: ""
                value: 100 * (1 - card.clock.pomRemaining() / Math.max(1, card.clock.pomTotal(card.clock.pomPhase)))
                color: card.clock.pomPhase === "focus" ? card.t.accent : card.t.good; track: card.t.border; ink: card.t.ink; mutedInk: card.t.muted; duration: 120
            }
            ColumnLayout {
                anchors.centerIn: parent; spacing: 0
                Text { text: card.fmt(card.clock.pomRemaining(), false); color: card.t.ink; font.pixelSize: 24; font.weight: Font.Light; Layout.alignment: Qt.AlignHCenter }
                Text { text: card.phaseNames[card.clock.pomPhase]; color: card.clock.pomPhase === "focus" ? card.t.accent : card.t.good; font.pixelSize: 11; font.weight: Font.DemiBold; Layout.alignment: Qt.AlignHCenter }
            }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: 6
            Repeater {
                model: 4
                delegate: Rectangle { required property int index; width: 9; height: 9; radius: 5; color: index < card.clock.pomCycle ? card.t.accent : "transparent"; border.color: index < card.clock.pomCycle ? card.t.accent : card.t.faint }
            }
            Text { text: "  Hoje: " + card.clock.pomToday + (card.clock.pomToday === 1 ? " pomodoro" : " pomodoros"); color: card.t.muted; font.pixelSize: 11 }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: 8
            Button { text: card.clock.pomRunning ? "Pausar" : "Iniciar"; solid: true; onClicked: card.clock.pomToggle() }
            Button { text: "Pular"; onClicked: card.clock.pomSkip() }
            Button { text: "Zerar"; onClicked: card.clock.pomReset() }
        }
    }
}
