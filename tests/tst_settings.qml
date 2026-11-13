import QtQuick
import QtTest
import "../package/contents/ui"
import "../package/contents/ui/quickitems.js" as QI

// Painel de configurações dentro do widget e a escolha dos botões das Ações rápidas.
Item {
    id: root
    width: 700; height: 640

    Theme { id: theme }
    QtObject {
        id: cfg
        property string themeMode: "dark"
        property int uiScale: 100
        property string density: "normal"
        property int iconScale: 100
        property string accentColor: "#3daee9"
        property int backgroundOpacity: 94
        property bool animations: true
        property string quickItems: ""
        property string userName: ""
        property string defaultProvider: "antigravity"
        property bool summaryEnabled: true
        property int summaryHour: 8
        property int eventLeadMinutes: 10
        property bool alertsEnabled: true
        property bool showNews: false
        property bool showQuick: true
    }
    // Layout de mentira: só o que o painel usa.
    QtObject {
        id: fakeShell
        property var sys: ({})
        property var speed: null
        property var clock: null
        property var allIds: ["chat", "news", "quick", "clock"]
        property var names: ({news: "Notícias", quick: "Ações rápidas", clock: "Cronômetro"})
        property var hiddenIds: ["quick"]
        function cardOn(id) { return id === "news" ? cfg.showNews : id === "quick" ? cfg.showQuick : id === "clock" ? !!clock : true }
        function hideCard(id) { hiddenIds = hiddenIds.concat([id]) }
        function showCard(id) { hiddenIds = hiddenIds.filter(x => x !== id) }
    }
    property int closed: 0
    property int more: 0
    SettingsPanel { id: panel; anchors.fill: parent; t: theme; cfg: cfg; host: fakeShell; onCloseRequested: root.closed++; onMoreRequested: root.more++ }

    function find(item, pred) {
        if (pred(item)) return item
        for (let i = 0; i < item.children.length; ++i) { const r = find(item.children[i], pred); if (r) return r }
        return null
    }
    function visibleItem(it) { for (let p = it; p; p = p.parent) if (!p.visible) return false; return it.width > 0 }
    function byText(text) { return find(panel, it => it.text === text && it.toggled === undefined && it.clicked === undefined && visibleItem(it)) }
    function toggleNamed(text) { return find(panel, it => it.toggled !== undefined && it.text === text && visibleItem(it)) }

    TestCase {
        name: "Configuracoes"
        when: windowShown
        function clickOn(item) { const p = item.mapToItem(root, item.width / 2, item.height / 2); mouseClick(root, p.x, p.y) }

        function init() { panel.section = "appearance"; cfg.quickItems = ""; cfg.themeMode = "dark"; cfg.showNews = false; fakeShell.hiddenIds = ["quick"]; wait(30) }

        function test_catalogo_das_acoes() {
            compare(QI.enabled(""), QI.ids(), "vazio = todos")
            compare(QI.enabled("lixo"), QI.ids())
            compare(QI.enabled('["lock","xyz","dnd","lock"]'), ["lock", "dnd"], "ignora desconhecidos e repetidos")
            const sem = QI.toggled("", "wifi")
            verify(JSON.parse(sem).indexOf("wifi") < 0)
            compare(JSON.parse(QI.toggled(sem, "wifi")).slice(-1), ["wifi"], "religado volta no fim")
            compare(JSON.parse(QI.moved('["a","dnd","night"]'.replace('"a",', ''), "night", -1)), ["night", "dnd"])
            compare(JSON.parse(QI.moved('["dnd","night"]', "dnd", -1)), ["dnd", "night"], "o primeiro não sobe")
        }

        function test_tema_muda_na_hora() {
            clickOn(byText("Claro").parent)
            compare(cfg.themeMode, "light")
            clickOn(find(panel, it => it.text === "Grande" && it.clicked !== undefined && visibleItem(it)))
            compare(cfg.uiScale, 125)
            cfg.uiScale = 100
        }

        function test_cartoes_ligam_e_entram_no_layout() {
            panel.section = "cards"; wait(30)
            const news = toggleNamed("Notícias")
            verify(news, "linha de Notícias")
            compare(news.on, false)
            clickOn(news)
            compare(cfg.showNews, true, "liga a configuração")
            wait(30)
            verify(fakeShell.hiddenIds.indexOf("news") < 0)
            compare(toggleNamed("Ações rápidas").on, false, "oculto no layout = desligado")
            clickOn(toggleNamed("Ações rápidas"))
            wait(30)
            compare(fakeShell.hiddenIds, [], "entrou no layout")
            clickOn(toggleNamed("Ações rápidas"))
            compare(fakeShell.hiddenIds, ["quick"], "desligar oculta")
            verify(!toggleNamed("Cronômetro").enabled, "sem o motor do cronômetro fica apagado")
        }

        function test_acoes_rapidas_escolher_e_ordenar() {
            panel.section = "quick"; wait(30)
            clickOn(toggleNamed("Wi-Fi"))
            verify(JSON.parse(cfg.quickItems).indexOf("wifi") < 0, "desligou o Wi-Fi")
            wait(30)
            const up = find(panel, it => it.tip === "Subir" && it.parent && it.parent.modelData && it.parent.modelData.id === "night" && visibleItem(it))
            verify(up)
            clickOn(up)
            compare(JSON.parse(cfg.quickItems).slice(0, 2), ["night", "dnd"])
            const flick = find(panel, it => it.flickableDirection !== undefined)
            flick.contentY = Math.max(0, flick.contentHeight - flick.height); wait(30)
            clickOn(find(panel, it => it.text === "Restaurar padrão" && it.clicked !== undefined && visibleItem(it)))
            compare(cfg.quickItems, "")
        }

        function test_concluir_e_mais_opcoes() {
            clickOn(find(panel, it => it.text === "Mais opções…" && it.clicked !== undefined))
            compare(root.more, 1)
            clickOn(find(panel, it => it.text === "Concluir" && it.clicked !== undefined))
            compare(root.closed, 1)
        }
    }
}
