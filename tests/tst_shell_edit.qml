import QtQuick
import QtTest
import "../package/contents/ui"
import "../package/contents/ui/bridge" as Backend

// Edição do layout com o mouse de verdade (eventos simulados): arrastar cartão, ocultar e puxar a divisão.
// Rodar: tests/run.sh (usa o qmltestrunner).
Item {
    id: root
    width: 1300; height: 820

    QtObject {
        id: cfg
        property string layout: ""
        property bool showSystem: true; property bool showConnections: true; property bool showCalendar: true
        property bool showMedia: true; property bool showNetwork: true; property bool showReminders: true; property bool showNews: true
        property string reminders: "[]"; property string userName: "Teste"
    }
    Theme { id: theme }
    Backend.ClaudeClient { id: claude }
    Backend.DashboardClient { id: dash }
    Backend.MediaClient { id: media }
    Backend.NetworkClient { id: network }
    Shell {
        id: shell
        anchors.fill: parent
        t: theme; client: claude; dash: dash; media: media; net: network; cfg: cfg
        onSaveLayout: json => root.saved.push(json)
        onEditRequested: on => shell.editing = on
    }
    property var saved: []

    function find(item, pred) {
        if (pred(item)) return item
        for (let i = 0; i < item.children.length; ++i) { const r = find(item.children[i], pred); if (r) return r }
        return null
    }
    function slot(id) { return find(shell, it => it.cardId === id && it.width > 0 && it.visible) }

    TestCase {
        name: "EdicaoDoLayout"
        when: windowShown

        function init() { shell.editing = false; shell.resetLayout(); root.saved = []; wait(150) }

        function test_modo_largo() { compare(shell.mode, "wide") }

        function test_arrastar_cartao_para_outra_coluna() {
            shell.editing = true; wait(300)
            const news = slot("news"), calendar = slot("calendar")
            verify(news && calendar, "cartões encontrados")
            compare(shell.colIds[3].indexOf("news"), 1)
            // Do cartão de notícias (coluna 4) para a metade de baixo do calendário (coluna 3).
            const from = news.mapToItem(root, news.width / 2, news.height / 2)
            const to = calendar.mapToItem(root, calendar.width / 2, calendar.height * 0.9)
            mousePress(root, from.x, from.y)
            mouseMove(root, from.x - 40, from.y - 20, 30)
            mouseMove(root, to.x, to.y, 30)
            compare(shell.dragId, "news")        // durante o arrasto
            mouseRelease(root, to.x, to.y)
            compare(shell.dragId, "")
            compare(shell.colIds[2], ["media", "calendar", "news"])
            compare(shell.colIds[3], ["reminders"])
            verify(root.saved.length >= 1, "layout salvo")
            verify(JSON.parse(root.saved[root.saved.length - 1]).cols[2].c.indexOf("news") >= 0)
        }

        function test_ocultar_e_trazer_de_volta() {
            shell.editing = true; wait(300)
            for (const id of ["reminders", "news"]) {
                const s = slot(id)
                const btn = find(s, it => it.tip === "Ocultar este cartão" && it.visible)
                verify(btn, "botão de ocultar de " + id)
                const p = btn.mapToItem(root, btn.width / 2, btn.height / 2)
                mouseClick(root, p.x, p.y)
                wait(250)
            }
            compare(shell.hiddenIds.slice().sort(), ["news", "reminders"])
            compare(shell.colIds[3], [])
            compare(shell.hiddenEnabled.length, 2)
            shell.showCard("news"); wait(100)
            compare(shell.hiddenIds, ["reminders"])
        }

        function test_puxar_divisao() {
            shell.editing = true; wait(300)
            const sp = find(shell, it => it.nextCol !== undefined && it.nextCol >= 0 && it.visible && it.width === 16)
            verify(sp, "divisão encontrada")
            const before = shell.colW.slice()
            const p = sp.mapToItem(root, 8, 100)
            mousePress(root, p.x, p.y)
            mouseMove(root, p.x + 20, p.y, 30)
            mouseMove(root, p.x + 80, p.y, 30)
            mouseRelease(root, p.x + 80, p.y)
            verify(shell.colW[sp.index] > before[sp.index] + 0.05, "coluna da esquerda ficou maior")
            verify(shell.colW[sp.nextCol] < before[sp.nextCol], "coluna da direita ficou menor")
            verify(root.saved.length >= 1, "largura salva")
        }

        function test_fora_do_modo_de_edicao_nada_arrasta() {
            const news = slot("news")
            const from = news.mapToItem(root, news.width / 2, news.height / 2)
            mousePress(root, from.x, from.y)
            mouseMove(root, from.x - 200, from.y, 30)
            mouseRelease(root, from.x - 200, from.y)
            compare(shell.dragId, "")
            compare(shell.colIds[3], ["reminders", "news"])
        }

        function test_layout_salvo_e_restaurado() {
            shell.moveCard("news", 0, 0)
            const json = root.saved[root.saved.length - 1]
            shell.applyLayout("lixo"); compare(shell.colIds[0][0], "system")   // texto inválido volta ao padrão
            shell.applyLayout(json)
            compare(shell.colIds[0][0], "news")
        }
    }
}
