import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as B
import org.kde.kirigami as Kirigami

// Uma mensagem do chat. Respostas da IA aparecem formatadas (Markdown) e selecionáveis.
Item {
    id: bubble
    required property var t
    required property var client
    required property string speaker
    required property string messageId
    required property int index
    required property string body
    required property var files
    property string assistantName: ""
    property int availableWidth: 400
    readonly property bool mine: speaker === "user"
    property bool copied: false
    property bool editing: false
    // Só a última mensagem da conversa pode ser regenerada; a pergunta pode ser editada se a IA estiver livre.
    readonly property bool isLast: index === client.messages.rowCount() - 1
    readonly property bool idle: client.ready && !client.busy
    width: availableWidth
    implicitHeight: column.implicitHeight

    HoverHandler { id: hover }
    Timer { id: copiedReset; interval: 1500; onTriggered: bubble.copied = false }
    function submitEdit() { const text = editor.text.trim(); if (text === "") return; editing = false; client.resend(messageId, text) }
    function copy() { client.copyText(body); copied = true; copiedReset.restart() }
    // Nas mensagens do usuário, o botão de copiar fica à esquerda do balão.
    Row {
        visible: bubble.mine && !bubble.editing
        anchors.right: column.left; anchors.rightMargin: 4; anchors.verticalCenter: column.verticalCenter
        spacing: 2
        IconButton {
            visible: bubble.idle
            t: bubble.t; size: 22; opacity: hover.hovered ? 1 : 0
            icon: "document-edit"; tip: "Editar e refazer a partir daqui"
            onClicked: { editor.text = bubble.body; bubble.editing = true; editor.forceActiveFocus() }
        }
        IconButton {
            t: bubble.t; size: 22; opacity: hover.hovered || bubble.copied ? 1 : 0
            icon: bubble.copied ? "checkmark" : "edit-copy"; tip: bubble.copied ? "Copiado" : "Copiar"
            onClicked: bubble.copy()
        }
    }

    ColumnLayout {
        id: column
        width: bubble.editing ? bubble.availableWidth * 0.92 : bubble.mine ? Math.min(bubble.availableWidth * 0.82, Math.max(content.implicitWidth, filesRow.implicitWidth) + 26) : bubble.availableWidth
        anchors.right: bubble.mine ? parent.right : undefined
        spacing: 4

        RowLayout {
            visible: !bubble.mine; spacing: 6
            // Ícone da IA que respondeu (pelo nome gravado na mensagem; sem nome, a IA atual).
            ProviderIcon {
                size: 16
                provider: {
                    const list = bubble.client.providers || []
                    for (const p of list) if (p.name === bubble.assistantName) return p.id
                    return bubble.client.provider || ""
                }
            }
            Text { text: bubble.assistantName || bubble.client.providerName || "IA"; color: bubble.t.muted; font.pixelSize: 11; font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
            IconButton {
                visible: bubble.isLast && bubble.idle
                t: bubble.t; size: 22; opacity: hover.hovered ? 1 : 0
                icon: "view-refresh"; tip: "Gerar a resposta de novo"
                onClicked: bubble.client.resend(bubble.messageId)
            }
            IconButton {
                t: bubble.t; size: 22; opacity: hover.hovered || bubble.copied ? 1 : 0
                icon: bubble.copied ? "checkmark" : "edit-copy"; tip: bubble.copied ? "Copiado" : "Copiar resposta"
                onClicked: bubble.copy()
            }
        }
        Flow {
            id: filesRow
            visible: bubble.files && bubble.files.length > 0
            Layout.fillWidth: true; spacing: 6
            Repeater {
                model: bubble.files || []
                delegate: Rectangle {
                    required property var modelData
                    height: 26; width: chipRow.implicitWidth + 14; radius: 8; color: bubble.t.cardRaised; border.color: bubble.t.border
                    Row {
                        id: chipRow; anchors.centerIn: parent; spacing: 5
                        Kirigami.Icon { source: modelData.kind === "image" ? "image-x-generic" : "text-x-generic"; width: 14; height: 14; isMask: true; color: bubble.t.muted; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData.name; color: bubble.t.ink; font.pixelSize: 11; elide: Text.ElideMiddle; width: Math.min(implicitWidth, 160); anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
        }
        Rectangle {
            visible: bubble.body !== "" && !bubble.editing
            Layout.fillWidth: true
            implicitHeight: content.implicitHeight + (bubble.mine ? 16 : 0)
            radius: 12
            color: bubble.mine ? bubble.t.accentSoft : "transparent"
            border.color: bubble.mine ? bubble.t.accentLine : "transparent"
            TextEdit {
                id: content
                x: bubble.mine ? 12 : 0; y: bubble.mine ? 8 : 0
                width: parent.width - (bubble.mine ? 24 : 0)
                text: bubble.body
                textFormat: bubble.mine ? TextEdit.PlainText : TextEdit.MarkdownText
                readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap
                color: bubble.t.ink; selectionColor: bubble.t.accentLine; selectedTextColor: bubble.t.ink
                font.pixelSize: 13
                onLinkActivated: link => Qt.openUrlExternally(link)
                HoverHandler { cursorShape: content.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
            }
        }
        // Edição da pergunta: o texto novo substitui esta mensagem e as seguintes.
        ColumnLayout {
            visible: bubble.editing
            Layout.fillWidth: true; spacing: 6
            B.TextArea {
                id: editor
                Layout.fillWidth: true
                wrapMode: TextEdit.Wrap; color: bubble.t.ink; font.pixelSize: 13
                selectionColor: bubble.t.accentLine; placeholderTextColor: bubble.t.faint
                leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
                background: Rectangle { radius: 12; color: bubble.t.cardRaised; border.color: bubble.t.accentLine }
                Keys.onPressed: event => {
                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) { event.accepted = true; bubble.submitEdit() }
                    else if (event.key === Qt.Key_Escape) { event.accepted = true; bubble.editing = false }
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight; spacing: 6
                IconButton { t: bubble.t; size: 26; icon: "dialog-cancel"; tip: "Cancelar"; onClicked: bubble.editing = false }
                IconButton { t: bubble.t; size: 26; primary: true; icon: "go-up"; tip: "Enviar a versão editada"; enabled: editor.text.trim() !== ""; onClicked: bubble.submitEdit() }
            }
        }
    }
}
