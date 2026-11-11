import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Volume, saída de áudio e brilho da tela.
Card {
    id: card
    required property var sys
    title: "Áudio e brilho"
    icon: "audio-volume-high-symbolic"

    readonly property real volume: sys.audioVolume
    function volumeIcon() {
        return sys.audioMuted || volume <= 0 ? "audio-volume-muted" : volume < 0.34 ? "audio-volume-low" : volume < 0.67 ? "audio-volume-medium" : "audio-volume-high"
    }
    readonly property string sinkName: {
        for (const s of sys.audioSinks) if (s.id === sys.audioSink) return s.name
        return ""
    }

    Text {
        visible: !card.sys.audioAvailable && !card.sys.brightnessAvailable
        text: "Não encontrei controle de áudio (precisa do PipeWire/PulseAudio) nem de brilho neste computador."
        color: card.t.faint; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
    }

    // Volume
    RowLayout {
        visible: card.sys.audioAvailable
        Layout.fillWidth: true; spacing: 8
        IconButton { t: card.t; icon: card.volumeIcon(); size: 28; tip: card.sys.audioMuted ? "Ativar o som" : "Silenciar"; active: card.sys.audioMuted; onClicked: card.sys.setAudioMuted(!card.sys.audioMuted) }
        LevelBar {
            t: card.t; Layout.fillWidth: true
            value: Math.min(1, card.volume); dimmed: card.sys.audioMuted
            color: card.volume > 1 ? card.t.warn : card.t.accent
            onMoved: v => card.sys.setAudioVolume(v)
        }
        Text { text: Math.round(card.volume * 100) + "%"; color: card.t.muted; font.pixelSize: 11; Layout.preferredWidth: 34; horizontalAlignment: Text.AlignRight }
    }

    // Saída
    RowLayout {
        visible: card.sys.audioAvailable
        Layout.fillWidth: true; spacing: 8
        Kirigami.Icon { source: "audio-speakers-symbolic"; implicitWidth: 15; implicitHeight: 15; isMask: true; color: card.t.faint }
        Text {
            visible: card.sys.audioSinks.length <= 1
            text: card.sinkName; color: card.t.muted; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true
        }
        SelectPill {
            visible: card.sys.audioSinks.length > 1
            t: card.t; Layout.fillWidth: true; tip: "Saída de áudio"
            options: card.sys.audioSinks.map(s => ({value: s.id, text: s.name}))
            value: card.sys.audioSink
            onPicked: v => card.sys.setAudioSink(v)
        }
    }

    Rectangle { visible: card.sys.audioAvailable && card.sys.brightnessAvailable; Layout.fillWidth: true; height: 1; color: card.t.border }

    // Brilho
    RowLayout {
        visible: card.sys.brightnessAvailable
        Layout.fillWidth: true; spacing: 8
        Kirigami.Icon { source: "brightness-high"; implicitWidth: 20; implicitHeight: 20; isMask: true; color: card.t.ink; Layout.preferredWidth: 28; Layout.preferredHeight: 28 }
        LevelBar { t: card.t; Layout.fillWidth: true; value: card.sys.brightness; color: card.t.warn; onMoved: v => card.sys.setBrightness(v) }
        Text { text: Math.round(card.sys.brightness * 100) + "%"; color: card.t.muted; font.pixelSize: 11; Layout.preferredWidth: 34; horizontalAlignment: Text.AlignRight }
    }
}
