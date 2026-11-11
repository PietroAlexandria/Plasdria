import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Dispositivos Bluetooth pareados: estado, bateria e conectar/desconectar com um toque.
Card {
    id: card
    required property var sys
    title: "Bluetooth"
    Component.onCompleted: sys.acquire("bluetooth")
    Component.onDestruction: sys.release("bluetooth")
    icon: "preferences-system-bluetooth-symbolic"

    actions: [
        IconButton {
            visible: card.sys.bluetoothAvailable
            t: card.t; icon: "network-bluetooth"; size: 22; active: card.sys.bluetoothPowered
            tip: card.sys.bluetoothPowered ? "Desligar o Bluetooth" : "Ligar o Bluetooth"
            onClicked: card.sys.setBluetoothPowered(!card.sys.bluetoothPowered)
        }
    ]

    Text {
        visible: !card.sys.bluetoothAvailable
        text: "Bluetooth indisponível neste computador."
        color: card.t.faint; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
    }
    ColumnLayout {
        visible: card.sys.bluetoothAvailable && !card.sys.bluetoothPowered
        spacing: 8; Layout.fillWidth: true
        Text {
            text: card.sys.bluetoothBlocked ? "Bluetooth desligado (bloqueado no sistema)." : "Bluetooth desligado."
            color: card.t.faint; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
        }
        Rectangle {
            Layout.preferredHeight: 28; Layout.preferredWidth: onText.implicitWidth + 28; radius: 14
            color: onHover.hovered ? card.t.accentSoft : "transparent"; border.color: card.t.accentLine
            Text { id: onText; anchors.centerIn: parent; text: "Ligar"; color: card.t.accent; font.pixelSize: 12; font.weight: Font.DemiBold }
            HoverHandler { id: onHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: card.sys.setBluetoothPowered(true) }
        }
    }
    Text {
        visible: card.sys.bluetoothPowered && card.sys.bluetoothDevices.length === 0
        text: "Nenhum dispositivo pareado."
        color: card.t.faint; font.pixelSize: 12; Layout.fillWidth: true
    }
    Repeater {
        model: card.sys.bluetoothPowered ? card.sys.bluetoothDevices : []
        delegate: Rectangle {
            required property var modelData
            Layout.fillWidth: true; height: 34; radius: 8
            color: rowHover.hovered ? card.t.cardRaised : "transparent"
            HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: card.sys.toggleBluetoothDevice(modelData.path) }
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 6; spacing: 9
                Kirigami.Icon {
                    source: modelData.icon || "preferences-system-bluetooth"; fallback: "preferences-system-bluetooth"
                    implicitWidth: 18; implicitHeight: 18; isMask: true
                    color: modelData.connected ? card.t.accent : card.t.faint
                }
                ColumnLayout {
                    spacing: 0; Layout.fillWidth: true
                    Text { text: modelData.name; color: modelData.connected ? card.t.ink : card.t.muted; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
                    Text { text: modelData.connected ? "Conectado" : "Desconectado · toque para conectar"; color: modelData.connected ? card.t.good : card.t.faint; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                }
                Rectangle {
                    visible: modelData.battery >= 0
                    Layout.preferredWidth: 38; height: 5; radius: 3; color: card.t.border
                    Rectangle { width: parent.width * Math.min(100, modelData.battery) / 100; height: parent.height; radius: 3; color: card.t.levelColor(modelData.battery) }
                }
                Text { visible: modelData.battery >= 0; text: modelData.battery + "%"; color: card.t.muted; font.pixelSize: 11; Layout.preferredWidth: 30; horizontalAlignment: Text.AlignRight }
            }
        }
    }
}
