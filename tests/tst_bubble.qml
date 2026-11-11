import QtQuick
import QtTest
import "../package/contents/ui"

// Botões de regenerar e editar nas mensagens, com um cliente de mentira.
Item {
    id: root
    width: 500; height: 400
    Theme { id: theme }
    QtObject {
        id: fake
        property bool ready: true
        property bool busy: false
        property string providerName: "IA"
        property var calls: []
        property var messages: ListModel { ListElement { speaker: "user"; body: "pergunta"; messageId: "u1"; files: "" }
                                           ListElement { speaker: "assistant"; body: "resposta"; messageId: "a1"; files: "" } }
        function resend(id, text) { calls = calls.concat([[id, text === undefined ? null : text]]); return true }
        function copyText(t) {}
    }
    ListView {
        id: list
        anchors.fill: parent
        model: fake.messages
        spacing: 10
        delegate: MessageBubble { t: theme; client: fake; availableWidth: list.width }
    }
    TestCase {
        name: "Bolha"
        when: windowShown
        function init() { fake.calls = []; fake.busy = false }
        function findButton(item, tip) {
            if (item.tip === tip) return item
            for (let i = 0; i < item.children.length; ++i) { const f = findButton(item.children[i], tip); if (f) return f }
            return null
        }
        function test_regenerar_so_na_ultima_e_com_ia_livre() {
            const user = list.itemAtIndex(0), ai = list.itemAtIndex(1)
            verify(findButton(ai, "Gerar a resposta de novo").visible)
            fake.busy = true
            verify(!findButton(ai, "Gerar a resposta de novo").visible, "escondido enquanto responde")
            verify(!findButton(user, "Editar e refazer a partir daqui").visible)
            fake.busy = false
            findButton(ai, "Gerar a resposta de novo").clicked()
            compare(fake.calls, [["a1", null]])
        }
        function test_editar_envia_o_texto_novo() {
            const user = list.itemAtIndex(0)
            compare(user.editing, false)
            findButton(user, "Editar e refazer a partir daqui").clicked()
            verify(user.editing)
            user.submitEdit()                       // o campo abre com a pergunta original
            compare(fake.calls, [["u1", "pergunta"]])
            verify(!user.editing)
        }
    }
}
