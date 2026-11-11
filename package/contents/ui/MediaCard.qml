import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Música tocando agora. Com o player fechado, mostra a última música e retoma de onde parou.
Card {
    id: card
    required property var media
    title: !media.available ? "Música"
         : media.launching ? "Abrindo " + (media.player || "Spotify") + "…"
         : !media.live ? "Última música · " + media.player
         : (media.playing ? "Tocando · " : "Pausado · ") + media.player
    icon: "media-playback-start-symbolic"
    function clock(seconds) {
        if (!(seconds > 0)) return "0:00"
        const s = Math.floor(seconds), h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), r = s % 60
        return (h > 0 ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(r).padStart(2, "0")
    }

    actions: [
        IconButton {
            t: card.t; icon: "spotify"; size: 22; colored: true
            visible: card.media.spotifyInstalled
            tip: card.media.live && card.media.isSpotify ? "Mostrar o Spotify" : "Abrir o Spotify"
            onClicked: card.media.openSpotify()
        }
    ]

    // Nada para mostrar
    ColumnLayout {
        visible: !card.media.available
        spacing: 8; Layout.fillWidth: true
        Text { text: "Nada tocando. Abra o Spotify, um vídeo ou qualquer player."; color: card.t.faint; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Rectangle {
            visible: card.media.spotifyInstalled
            Layout.preferredHeight: 30; Layout.preferredWidth: openRow.implicitWidth + 24; radius: 15
            color: openHover.hovered ? Qt.rgba(0.11, 0.73, 0.33, 0.28) : Qt.rgba(0.11, 0.73, 0.33, 0.16)
            border.color: Qt.rgba(0.11, 0.73, 0.33, 0.5)
            RowLayout {
                id: openRow; anchors.centerIn: parent; spacing: 6
                Kirigami.Icon { source: "spotify"; implicitWidth: 16; implicitHeight: 16 }
                Text { text: "Abrir o Spotify"; color: card.t.spotify; font.pixelSize: 12; font.weight: Font.DemiBold }
            }
            HoverHandler { id: openHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: card.media.openSpotify() }
        }
    }

    RowLayout {
        visible: card.media.available
        spacing: 12; Layout.fillWidth: true
        Rectangle {
            Layout.preferredWidth: 64; Layout.preferredHeight: 64
            radius: 10; color: card.t.cardRaised; clip: true
            Image {
                id: art
                anchors.fill: parent
                source: card.media.artUrl; fillMode: Image.PreserveAspectCrop
                asynchronous: true; sourceSize: Qt.size(128, 128)
                visible: status === Image.Ready
                opacity: card.media.live ? 1 : 0.55
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
            Kirigami.Icon { anchors.centerIn: parent; visible: !art.visible; source: "media-album-cover"; width: 28; height: 28; isMask: true; color: card.t.faint }
            // Sem o player aberto: botão grande de retomar sobre a capa.
            Rectangle {
                visible: !card.media.live
                anchors.centerIn: parent; width: 30; height: 30; radius: 15
                color: Qt.rgba(0, 0, 0, 0.55)
                Kirigami.Icon { anchors.centerIn: parent; source: card.media.launching ? "view-refresh" : "media-playback-start"; width: 16; height: 16; color: "white"; isMask: true
                    RotationAnimation on rotation { running: card.media.launching; from: 0; to: 360; duration: 900; loops: Animation.Infinite } }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: card.media.live ? card.media.raise() : card.media.playPause() }
        }
        ColumnLayout {
            spacing: 1; Layout.fillWidth: true
            Text { text: card.media.title || "Sem título"; color: card.t.ink; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true; maximumLineCount: 2; wrapMode: Text.Wrap }
            Text { text: card.media.artist || card.media.album || ""; visible: text !== ""; color: card.t.muted; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
            Text {
                visible: !card.media.live
                text: card.media.launching ? "Abrindo o player para continuar…" : "Player fechado · toque para continuar"
                color: card.t.faint; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true
            }
        }
    }
    ColumnLayout {
        visible: card.media.available && card.media.length > 0
        spacing: 2; Layout.fillWidth: true
        Item {
            Layout.fillWidth: true; height: 12
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: seekHover.hovered && card.media.canSeek ? 6 : 4; radius: 3; color: card.t.border
                Behavior on height { NumberAnimation { duration: 120 } }
                Rectangle { width: parent.width * Math.min(1, card.media.position / Math.max(1, card.media.length)); height: parent.height; radius: 3; color: card.media.live ? card.t.accent : card.t.faint }
            }
            HoverHandler { id: seekHover; cursorShape: card.media.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: card.media.canSeek; onTapped: point => card.media.seek(card.media.length * point.position.x / parent.width) }
        }
        RowLayout {
            Text { text: card.clock(card.media.position); color: card.t.faint; font.pixelSize: 10 }
            Item { Layout.fillWidth: true }
            Text { text: card.clock(card.media.length); color: card.t.faint; font.pixelSize: 10 }
        }
    }
    RowLayout {
        visible: card.media.available
        Layout.fillWidth: true; spacing: 6
        IconButton {
            t: card.t; icon: "media-playlist-shuffle"; size: 26
            visible: card.media.hasShuffle
            tip: card.media.shuffle ? "Aleatório: ligado" : "Aleatório: desligado"
            active: card.media.shuffle
            onClicked: card.media.setShuffle(!card.media.shuffle)
        }
        Item { Layout.fillWidth: true }
        IconButton { t: card.t; icon: "media-skip-backward"; tip: "Anterior"; enabled: card.media.canGoPrevious; onClicked: card.media.previous() }
        IconButton {
            t: card.t; primary: true; size: 34
            icon: card.media.launching ? "view-refresh" : card.media.playing ? "media-playback-pause" : "media-playback-start"
            tip: !card.media.live ? "Abrir e continuar de onde parou" : card.media.playing ? "Pausar" : "Tocar"
            onClicked: card.media.playPause()
        }
        IconButton { t: card.t; icon: "media-skip-forward"; tip: "Próxima"; enabled: card.media.canGoNext; onClicked: card.media.next() }
        Item { Layout.fillWidth: true }
        IconButton {
            t: card.t; size: 26
            visible: card.media.loopStatus !== ""
            icon: card.media.loopStatus === "Track" ? "media-repeat-single" : "media-repeat-all"
            active: card.media.loopStatus === "Track" || card.media.loopStatus === "Playlist"
            tip: card.media.loopStatus === "Track" ? "Repetir: esta música" : card.media.loopStatus === "Playlist" ? "Repetir: tudo" : "Repetir: desligado"
            onClicked: card.media.cycleLoop()
        }
    }
    // Volume do player
    RowLayout {
        visible: card.media.volume >= 0
        Layout.fillWidth: true; spacing: 8
        Kirigami.Icon {
            source: card.media.volume <= 0 ? "audio-volume-muted" : card.media.volume < 0.4 ? "audio-volume-low" : card.media.volume < 0.75 ? "audio-volume-medium" : "audio-volume-high"
            implicitWidth: 14; implicitHeight: 14; isMask: true; color: card.t.muted
            TapHandler { onTapped: card.media.setVolume(card.media.volume > 0 ? 0 : 0.7) }
        }
        Item {
            id: volumeBar
            Layout.fillWidth: true; height: 14
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: card.t.border
                Rectangle { width: parent.width * card.media.volume; height: parent.height; radius: 2; color: card.t.muted }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            DragHandler { target: null; xAxis.enabled: true; yAxis.enabled: false; onCentroidChanged: if (active) card.media.setVolume(centroid.position.x / volumeBar.width) }
            TapHandler { onTapped: point => card.media.setVolume(point.position.x / volumeBar.width) }
        }
        Text { text: Math.round(card.media.volume * 100) + "%"; color: card.t.faint; font.pixelSize: 10; Layout.preferredWidth: 28; horizontalAlignment: Text.AlignRight }
    }
}
