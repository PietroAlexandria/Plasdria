import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as B
import org.kde.kirigami as Kirigami

// Atalhos para aplicativos, sites e pastas. A lista fica nas configurações do widget (texto JSON).
// Só abre aplicativos instalados, endereços http/https/mailto e arquivos ou pastas: nunca comandos de terminal.
Card {
    id: card
    required property var sys
    property string stored: "[]"
    signal save(string json)
    title: "Atalhos"
    icon: "emblem-favorite-symbolic"

    property var items: { try { const v = JSON.parse(stored); return Array.isArray(v) ? v : [] } catch (e) { return [] } }
    property bool adding: false
    property string mode: "app"          // "app" ou "link"
    property var apps: []
    readonly property var filtered: {
        const q = search.text.trim().toLowerCase()
        return apps.filter(a => q === "" || a.name.toLowerCase().indexOf(q) >= 0).slice(0, 60)
    }
    function commit(list) { save(JSON.stringify(list)) }
    function startAdding() { if (apps.length === 0) apps = sys.applications(); adding = true; search.text = ""; linkText.text = "" }
    function addApp(app) { commit(items.concat([{name: app.name, target: "app:" + app.id, icon: app.icon || "application-x-executable"}])); adding = false }
    function linkName(text) {
        if (/^https?:\/\//i.test(text)) return text.replace(/^https?:\/\/(www\.)?/i, "").split(/[\/?#]/)[0]
        if (/^mailto:/i.test(text)) return text.slice(7)
        return text.replace(/\/+$/, "").split("/").pop() || text
    }
    function validLink(text) { return /^(https?:\/\/\S+|mailto:\S+|~\/\S*|\/\S*|file:\/\/\S+)$/i.test(text.trim()) }
    function addLink() {
        const text = linkText.text.trim()
        if (!validLink(text)) return
        const web = /^(https?|mailto):/i.test(text)
        commit(items.concat([{name: linkName(text), target: text, icon: web ? "internet-web-browser" : (text.replace(/\/+$/, "").split("/").pop().indexOf(".") > 0 ? "text-x-generic" : "folder")}]))
        adding = false
    }
    function remove(index) { commit(items.filter((x, i) => i !== index)) }

    actions: [
        IconButton { t: card.t; icon: card.adding ? "dialog-close" : "list-add"; size: 22; tip: card.adding ? "Cancelar" : "Adicionar atalho"; onClicked: card.adding ? card.adding = false : card.startAdding() }
    ]

    Text {
        visible: card.items.length === 0 && !card.adding
        text: "Adicione seus aplicativos, sites e pastas favoritos para abrir com um toque."
        color: card.t.faint; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
    }

    // Grade de atalhos
    Flow {
        visible: card.items.length > 0
        Layout.fillWidth: true; spacing: 6
        Repeater {
            model: card.items
            delegate: Rectangle {
                id: tile
                required property var modelData
                required property int index
                width: 66; height: 62; radius: 10
                color: tileHover.hovered ? card.t.cardRaised : "transparent"
                HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: card.sys.launch(tile.modelData.target) }
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 4; spacing: 3
                    Kirigami.Icon { source: tile.modelData.icon || "application-x-executable"; fallback: "application-x-executable"; Layout.alignment: Qt.AlignHCenter; implicitWidth: 28; implicitHeight: 28 }
                    Text { text: tile.modelData.name; color: card.t.muted; font.pixelSize: 10; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                }
                IconButton {
                    visible: tileHover.hovered
                    t: card.t; icon: "edit-delete-remove"; size: 18; tip: "Remover atalho"
                    anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 1
                    onClicked: card.remove(tile.index)
                }
            }
        }
    }

    // Adicionar
    ColumnLayout {
        visible: card.adding
        Layout.fillWidth: true; spacing: 6
        Row {
            spacing: 6
            Repeater {
                model: [{id: "app", name: "Aplicativo"}, {id: "link", name: "Site ou pasta"}]
                delegate: Rectangle {
                    required property var modelData
                    height: 22; width: modeText.implicitWidth + 18; radius: 11
                    color: card.mode === modelData.id ? card.t.accentSoft : "transparent"
                    border.color: card.mode === modelData.id ? card.t.accentLine : card.t.border
                    Text { id: modeText; anchors.centerIn: parent; text: modelData.name; color: card.mode === modelData.id ? card.t.accent : card.t.muted; font.pixelSize: 11; font.weight: Font.DemiBold }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: card.mode = modelData.id }
                }
            }
        }
        B.TextField {
            id: search
            visible: card.mode === "app"
            Layout.fillWidth: true
            placeholderText: "Buscar aplicativo…"; placeholderTextColor: card.t.faint
            color: card.t.ink; font.pixelSize: 12; leftPadding: 10; topPadding: 6; bottomPadding: 6
            background: Rectangle { radius: 8; color: card.t.cardRaised; border.color: search.activeFocus ? card.t.accentLine : "transparent" }
        }
        ListView {
            visible: card.mode === "app"
            Layout.fillWidth: true; Layout.preferredHeight: Math.min(180, count * 32); clip: true
            model: card.filtered
            B.ScrollBar.vertical: B.ScrollBar { policy: B.ScrollBar.AsNeeded; width: 6 }
            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width - 8; height: 32; radius: 7
                color: appHover.hovered ? card.t.accentSoft : "transparent"
                HoverHandler { id: appHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: card.addApp(modelData) }
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6; spacing: 8
                    Kirigami.Icon { source: modelData.icon || "application-x-executable"; fallback: "application-x-executable"; implicitWidth: 20; implicitHeight: 20 }
                    Text { text: modelData.name; color: card.t.ink; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
                }
            }
        }
        B.TextField {
            id: linkText
            visible: card.mode === "link"
            Layout.fillWidth: true
            placeholderText: "https://… ou /caminho/da/pasta"; placeholderTextColor: card.t.faint
            color: card.t.ink; font.pixelSize: 12; leftPadding: 10; topPadding: 6; bottomPadding: 6
            background: Rectangle { radius: 8; color: card.t.cardRaised; border.color: linkText.activeFocus ? card.t.accentLine : "transparent" }
            onAccepted: card.addLink()
        }
        Text {
            visible: card.mode === "link"
            text: linkText.text !== "" && !card.validLink(linkText.text) ? "Use um endereço http(s), mailto ou um caminho (/…, ~/…)." : "Enter adiciona. Só abre sites, e-mails, arquivos e pastas."
            color: linkText.text !== "" && !card.validLink(linkText.text) ? card.t.warn : card.t.faint; font.pixelSize: 10; wrapMode: Text.Wrap; Layout.fillWidth: true
        }
    }
}
