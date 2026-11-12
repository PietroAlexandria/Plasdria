import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as B
import QtQuick.Dialogs
import QtCore
import org.kde.kirigami as Kirigami

// Chat de IA (Antigravity, Claude, Codex, Gemini, Ollama, API Compatível): cabeçalho com seletor de IA, modelo e cotas, mensagens, anexos e campo de envio.
Rectangle {
    id: chat
    required property var t
    required property var client
    radius: t.radius
    color: t.card
    border.color: dropArea.containsDrag ? t.accent : t.border

    readonly property var effortNames: ({low: "Baixo", medium: "Médio", high: "Alto", xhigh: "Extra alto", max: "Máximo"})
    readonly property var suggestions: [
        "Resuma as principais notícias de hoje",
        "Me ajude a escrever uma mensagem educada",
        "Explique um conceito de forma simples",
        "Monte um plano de estudos para esta semana"
    ]
    function remaining(reset) {
        const s = reset - Date.now() / 1000
        if (!(reset > 0) || s <= 0) return ""
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
        return d > 0 ? d + "d " + h + "h" : h > 0 ? h + "h " + m + "min" : m + "min"
    }
    function submit() {
        const text = input.text
        if (chat.client.send(text)) input.text = ""
    }
    function focusInput() { input.forceActiveFocus() }

    property real now: Date.now()
    Timer { interval: 30000; running: true; repeat: true; onTriggered: chat.now = Date.now() }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: chat.t.pad
        spacing: 10

        // Cabeçalho
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Image {
                source: "assets/icon.png"
                Layout.preferredWidth: 32; Layout.preferredHeight: 32
                sourceSize: Qt.size(64, 64); smooth: true; mipmap: true
                SequentialAnimation on scale {
                    running: chat.client.busy && chat.t.animations; loops: Animation.Infinite
                    onRunningChanged: if (!running) parent.scale = 1
                    NumberAnimation { to: 1.12; duration: 600; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                }
            }
            ColumnLayout {
                spacing: 0; Layout.fillWidth: true; Layout.minimumWidth: 40
                Rectangle {
                    id: providerBtn
                    Layout.maximumWidth: implicitWidth
                    implicitWidth: providerRow.implicitWidth + 10; implicitHeight: 22; radius: 7
                    color: (providerHover.hovered || providerMenu.opened) && !chat.client.busy ? chat.t.cardRaised : "transparent"
                    RowLayout {
                        id: providerRow; anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 4; spacing: 5
                        Text { text: chat.client.providerName; color: chat.t.ink; font.pixelSize: 15; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.alignment: Qt.AlignVCenter }
                        Kirigami.Icon { source: "arrow-down"; implicitWidth: 10; implicitHeight: 10; isMask: true; color: chat.t.muted; Layout.alignment: Qt.AlignVCenter }
                    }
                    HoverHandler { id: providerHover; cursorShape: chat.client.busy ? Qt.ArrowCursor : Qt.PointingHandCursor }
                    TapHandler { enabled: !chat.client.busy; onTapped: providerMenu.opened ? providerMenu.close() : providerMenu.open() }
                    B.ToolTip.visible: providerHover.hovered && !providerMenu.opened
                    B.ToolTip.text: "Alternar IA (Antigravity, Claude e outras)"
                    B.ToolTip.delay: 500

                    B.Popup {
                        id: providerMenu
                        y: providerBtn.height + 4
                        padding: 5
                        width: 245
                        background: Rectangle { color: chat.t.cardRaised; radius: 11; border.color: chat.t.border }
                        contentItem: Column {
                            spacing: 2
                            Repeater {
                                model: chat.client.providers
                                delegate: Rectangle {
                                    required property var modelData
                                    width: providerMenu.width - 10; height: 38; radius: 8
                                    color: pItemHover.hovered ? chat.t.accentSoft : "transparent"
                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                                        Rectangle {
                                            width: 7; height: 7; radius: 4
                                            color: modelData.id === chat.client.provider ? chat.t.accent : (modelData.available ? chat.t.good : chat.t.faint)
                                        }
                                        ColumnLayout {
                                            spacing: 0; Layout.fillWidth: true
                                            Text {
                                                text: modelData.name; font.pixelSize: 12
                                                color: modelData.id === chat.client.provider ? chat.t.accent : chat.t.ink
                                                font.weight: modelData.id === chat.client.provider ? Font.DemiBold : Font.Medium
                                                elide: Text.ElideRight; Layout.fillWidth: true
                                            }
                                            Text {
                                                text: modelData.subtitle || ""; font.pixelSize: 10
                                                color: chat.t.muted; elide: Text.ElideRight; Layout.fillWidth: true
                                            }
                                        }
                                    }
                                    HoverHandler { id: pItemHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: { providerMenu.close(); chat.client.provider = modelData.id } }
                                }
                            }
                        }
                    }
                }
                RowLayout {
                    spacing: 5
                    Rectangle { width: 6; height: 6; radius: 3; color: chat.client.error ? chat.t.bad : chat.client.ready ? chat.t.good : chat.t.warn }
                    Text { text: chat.client.status + (chat.client.plan ? " · " + chat.client.plan : ""); color: chat.t.muted; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                }
            }
            IconButton { t: chat.t; icon: "view-history"; tip: "Conversas anteriores"; active: history.opened; onClicked: history.opened ? history.close() : history.open() }
            IconButton { t: chat.t; icon: "document-save"; tip: "Exportar a conversa (Markdown)"; enabled: chat.client.messages.rowCount() > 0; onClicked: exportDialog.open() }
            IconButton { t: chat.t; icon: "list-add"; tip: "Nova conversa"; enabled: !chat.client.busy; onClicked: { chat.client.newChat(); input.forceActiveFocus() } }
        }

        // Modelo e esforço
        RowLayout {
            Layout.fillWidth: true; spacing: 6
            SelectPill {
                    t: chat.t; tip: "Modelo"
                    enabled: !chat.client.busy && chat.client.models.length > 0
                    options: chat.client.models.map(m => ({value: m.id, text: m.name}))
                    value: chat.client.model
                    onPicked: v => chat.client.model = v
                }
                SelectPill {
                    t: chat.t; tip: "Esforço de raciocínio"
                    visible: chat.client.efforts.length > 0
                    enabled: !chat.client.busy
                    options: chat.client.efforts.map(e => ({value: e, text: chat.effortNames[e] || e}))
                    value: chat.client.effort
                    onPicked: v => chat.client.effort = v
                }
            Item { Layout.fillWidth: true }
        }

        // Cotas
        RowLayout {
            visible: chat.client.hasQuota
            Layout.fillWidth: true; spacing: 14
            Repeater {
                model: [
                    {name: "5 horas", used: chat.client.fiveHourUsed, reset: chat.client.fiveHourReset},
                    {name: "Semana", used: chat.client.weeklyUsed, reset: chat.client.weeklyReset}
                ]
                delegate: ColumnLayout {
                    id: quota
                    required property var modelData
                    readonly property real free: modelData.used < 0 ? -1 : 100 - modelData.used
                    spacing: 3; Layout.fillWidth: true
                    RowLayout {
                        Text { text: modelData.name; color: chat.t.muted; font.pixelSize: 10 }
                        Text { text: { chat.now; const r = chat.remaining(modelData.reset); return r ? "· renova em " + r : "" } color: chat.t.faint; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { text: quota.free < 0 ? "—" : Math.round(quota.free) + "% livre"; color: chat.t.levelColor(quota.free); font.pixelSize: 10; font.weight: Font.DemiBold }
                    }
                    Rectangle {
                        Layout.fillWidth: true; height: 4; radius: 2; color: chat.t.border
                        Rectangle {
                            width: parent.width * Math.max(0, quota.free) / 100; height: parent.height; radius: 2
                            color: chat.t.levelColor(quota.free)
                            Behavior on width { NumberAnimation { duration: chat.t.animations ? 500 : 0; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }

        // Erros
        Rectangle {
            visible: chat.client.error !== ""
            Layout.fillWidth: true; radius: 10
            implicitHeight: errorRow.implicitHeight + 14
            color: Qt.rgba(chat.t.bad.r, chat.t.bad.g, chat.t.bad.b, 0.12)
            border.color: Qt.rgba(chat.t.bad.r, chat.t.bad.g, chat.t.bad.b, 0.4)
            RowLayout {
                id: errorRow
                anchors.fill: parent; anchors.margins: 7; spacing: 8
                Kirigami.Icon { source: "dialog-warning"; implicitWidth: 16; implicitHeight: 16; isMask: true; color: chat.t.bad }
                Text { text: chat.client.error; color: chat.t.ink; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }
                B.Button {
                    text: "Reconectar"; visible: !chat.client.ready
                    onClicked: chat.client.reconnect()
                    contentItem: Text { text: parent.text; color: chat.t.ink; font.pixelSize: 11 }
                    background: Rectangle { radius: 7; color: chat.t.cardRaised; border.color: chat.t.border }
                }
            }
        }

        // Mensagens + histórico por cima
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true

            ListView {
                id: messages
                anchors.fill: parent
                clip: true; spacing: 14
                model: chat.client.messages
                boundsBehavior: Flickable.StopAtBounds
                B.ScrollBar.vertical: B.ScrollBar { policy: B.ScrollBar.AsNeeded }
                delegate: MessageBubble {
                    t: chat.t; client: chat.client
                    availableWidth: messages.width - 12
                }
                footer: Item {
                    width: messages.width; height: chat.client.busy ? 34 : 0; visible: chat.client.busy
                    Row {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 5
                        Repeater {
                            model: 3
                            delegate: Rectangle {
                                required property int index
                                width: 7; height: 7; radius: 4; color: chat.t.accent
                                anchors.verticalCenter: parent.verticalCenter
                                SequentialAnimation on opacity {
                                    running: chat.client.busy; loops: Animation.Infinite
                                    PauseAnimation { duration: index * 160 }
                                    NumberAnimation { from: 0.25; to: 1; duration: 320 }
                                    NumberAnimation { from: 1; to: 0.25; duration: 320 }
                                    PauseAnimation { duration: (2 - index) * 160 }
                                }
                            }
                        }
                        Text { text: chat.client.status + "…"; color: chat.t.muted; font.pixelSize: 11; leftPadding: 4; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                onCountChanged: Qt.callLater(positionViewAtEnd)
                Connections { target: chat.client; function onScrollToLatest() { Qt.callLater(messages.positionViewAtEnd) } }
            }

            // Estado vazio com sugestões
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 20, 420)
                visible: messages.count === 0 && !chat.client.conversationLoading
                spacing: 10
                Text { text: "Como posso ajudar?"; color: chat.t.ink; font.pixelSize: 20; font.weight: Font.Light; Layout.alignment: Qt.AlignHCenter }
                Text { text: "Pergunte qualquer coisa, anexe arquivos ou retome uma conversa anterior."; color: chat.t.muted; font.pixelSize: 12; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                GridLayout {
                    columns: width > 340 ? 2 : 1; Layout.fillWidth: true; Layout.topMargin: 6
                    columnSpacing: 8; rowSpacing: 8
                    Repeater {
                        model: chat.suggestions
                        delegate: Rectangle {
                            required property string modelData
                            Layout.fillWidth: true; implicitHeight: sugg.implicitHeight + 18; radius: 10
                            color: sHover.hovered ? chat.t.accentSoft : chat.t.cardRaised
                            border.color: sHover.hovered ? chat.t.accentLine : chat.t.border
                            enabled: chat.client.ready
                            opacity: enabled ? 1 : 0.5
                            Text { id: sugg; anchors.fill: parent; anchors.margins: 9; text: modelData; color: chat.t.ink; font.pixelSize: 12; wrapMode: Text.Wrap; verticalAlignment: Text.AlignVCenter }
                            HoverHandler { id: sHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: chat.client.send(modelData) }
                        }
                    }
                }
            }

            HistoryOverlay { id: history; anchors.fill: parent; t: chat.t; client: chat.client; z: 10 }
        }

        // Anexos pendentes
        Flow {
            visible: chat.client.attachments.length > 0 || chat.client.attachmentError !== ""
            Layout.fillWidth: true; spacing: 6
            Repeater {
                model: chat.client.attachments
                delegate: Rectangle {
                    required property var modelData
                    height: 34; width: chip.implicitWidth + 12; radius: 9; color: chat.t.cardRaised; border.color: chat.t.border
                    Row {
                        id: chip; anchors.centerIn: parent; spacing: 6
                        Image { visible: modelData.preview !== ""; source: modelData.preview; width: 24; height: 24; fillMode: Image.PreserveAspectCrop; anchors.verticalCenter: parent.verticalCenter }
                        Kirigami.Icon { visible: modelData.preview === ""; source: "text-x-generic"; width: 16; height: 16; isMask: true; color: chat.t.muted; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData.name; color: chat.t.ink; font.pixelSize: 11; elide: Text.ElideMiddle; width: Math.min(implicitWidth, 150); anchors.verticalCenter: parent.verticalCenter }
                        IconButton { t: chat.t; icon: "window-close"; size: 18; tip: "Remover"; onClicked: chat.client.removeAttachment(modelData.id); anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
            Text {
                visible: chat.client.attachmentError !== ""
                text: chat.client.attachmentError; color: chat.t.bad; font.pixelSize: 11; height: 34; verticalAlignment: Text.AlignVCenter
            }
        }

        // Campo de envio
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.min(140, Math.max(46, input.implicitHeight + 16))
            radius: 12
            color: chat.t.cardRaised
            border.color: input.activeFocus ? chat.t.accentLine : chat.t.border
            Behavior on border.color { ColorAnimation { duration: chat.t.duration } }
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 7; spacing: 4
                IconButton { t: chat.t; icon: "mail-attachment"; tip: "Anexar arquivos"; enabled: !chat.client.busy; onClicked: fileDialog.open(); Layout.alignment: Qt.AlignVCenter }
                B.ScrollView {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    B.TextArea {
                        id: input
                        placeholderText: chat.client.ready ? "Pergunte ao " + chat.client.providerName + "…" : "Conectando ao " + chat.client.providerName + "…"
                        placeholderTextColor: chat.t.faint
                        color: chat.t.ink; font.pixelSize: 13; wrapMode: TextEdit.Wrap
                        selectionColor: chat.t.accentLine
                        topPadding: 12; bottomPadding: 12; leftPadding: 4
                        background: null
                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                event.accepted = true; chat.submit()
                            } else if (event.key === Qt.Key_Escape && chat.client.busy) {
                                event.accepted = true; chat.client.stop()
                            }
                        }
                    }
                }
                IconButton {
                    t: chat.t; size: 32; primary: true; Layout.alignment: Qt.AlignVCenter
                    icon: chat.client.busy ? "media-playback-stop" : "go-up"
                    tip: chat.client.busy ? "Parar resposta" : "Enviar"
                    enabled: chat.client.busy || (chat.client.ready && (input.text.trim() !== "" || chat.client.attachments.length > 0))
                    onClicked: chat.client.busy ? chat.client.stop() : chat.submit()
                }
            }
        }
    }

    DropArea {
        id: dropArea
        anchors.fill: parent
        onDropped: drop => { for (const url of drop.urls) chat.client.addAttachment(url) }
    }
    FileDialog {
        id: exportDialog
        title: "Exportar a conversa"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Markdown (*.md)"]
        defaultSuffix: "md"
        currentFolder: StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
        currentFile: currentFolder + "/conversa-" + Qt.formatDate(new Date(), "yyyy-MM-dd") + ".md"
        onAccepted: chat.client.exportConversation(selectedFile)
    }
    FileDialog {
        id: fileDialog
        title: "Anexar arquivos"
        fileMode: FileDialog.OpenFiles
        onAccepted: { for (const url of selectedFiles) chat.client.addAttachment(url) }
    }
}
