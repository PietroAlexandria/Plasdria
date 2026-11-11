import QtQuick
import QtTest
import "../package/contents/ui"
import "../package/contents/ui/bridge" as Backend

// Cartões novos (atalhos, áudio e brilho, Bluetooth, maiores consumidores) com um "sistema" de mentira,
// mais a recusa de alvos perigosos pelo SystemClient real (que nunca executa comandos de terminal).
Item {
    id: root
    width: 420; height: 900

    Theme { id: theme }
    Backend.SystemClient { id: realSystem }

    // Sistema de mentira: registra o que os cartões pedem.
    QtObject {
        id: fake
        property var calls: []
        property bool audioAvailable: true
        property real audioVolume: 0.5
        property bool audioMuted: false
        property string audioSink: "a"
        property var audioSinks: [{id: "a", name: "Alto-falantes"}, {id: "b", name: "Fone USB"}]
        property bool brightnessAvailable: true
        property real brightness: 0.4
        property bool bluetoothAvailable: true
        property bool bluetoothPowered: true
        property bool bluetoothBlocked: false
        property var bluetoothDevices: [
            {path: "/dev/1", name: "Fone do João", icon: "audio-headset", connected: true, battery: 72},
            {path: "/dev/2", name: "Mouse", icon: "input-mouse", connected: false, battery: -1}]
        property var topCpu: [{name: "firefox", cpu: 12.5, memory: 1.5e9, count: 8}, {name: "plasmashell", cpu: 2.1, memory: 4e8, count: 1}]
        property var topMemory: [{name: "firefox", cpu: 12.5, memory: 1.5e9, count: 8}]
        property int acquired: 0
        property var topics: ({})
        function acquire(t) { topics[t] = (topics[t] || 0) + 1 }
        function release(t) { topics[t] = (topics[t] || 0) - 1 }
        function acquireTop() { acquired++ }
        function releaseTop() { acquired-- }
        function setAudioVolume(v) { calls.push("volume " + v.toFixed(2)); audioVolume = v }
        function setAudioMuted(m) { calls.push("mute " + m); audioMuted = m }
        function setAudioSink(id) { calls.push("sink " + id) }
        function setBrightness(v) { calls.push("brilho " + v.toFixed(2)) }
        function setBluetoothPowered(on) { calls.push("bt " + on) }
        function toggleBluetoothDevice(p) { calls.push("toggle " + p) }
        function applications() { return [{id: "firefox", name: "Firefox", icon: "firefox"}, {id: "konsole", name: "Konsole", icon: "utilities-terminal"}] }
        function launch(t) { calls.push("launch " + t); return true }
    }

    property string saved: "[]"
    ShortcutsCard { id: shortcuts; t: theme; sys: fake; stored: root.saved; width: 400; onSave: json => root.saved = json }
    AudioCard { id: audio; t: theme; sys: fake; width: 400; y: 300 }
    BluetoothCard { id: bluetooth; t: theme; sys: fake; width: 400; y: 450 }
    TopCard { id: top; t: theme; sys: fake; width: 400; y: 620 }

    function find(item, pred) {
        if (pred(item)) return item
        for (let i = 0; i < item.children.length; ++i) { const r = find(item.children[i], pred); if (r) return r }
        return null
    }

    TestCase {
        name: "CartoesNovos"
        when: windowShown

        function init() { fake.calls = []; root.saved = "[]"; fake.audioVolume = 0.5; fake.audioMuted = false }

        function test_atalhos_adicionar_app_e_abrir() {
            shortcuts.startAdding(); wait(100)
            compare(shortcuts.filtered.length, 2)
            shortcuts.addApp(shortcuts.apps[0])
            compare(JSON.parse(root.saved), [{name: "Firefox", target: "app:firefox", icon: "firefox"}])
            wait(150)
            const tile = find(shortcuts, it => it.modelData !== undefined && it.modelData.target === "app:firefox" && it.width === 66)
            verify(tile, "atalho aparece na grade")
            const p = tile.mapToItem(root, tile.width / 2, tile.height / 2)
            mouseClick(root, p.x, p.y)
            compare(fake.calls, ["launch app:firefox"])
        }

        function test_atalhos_links_e_pastas() {
            compare(shortcuts.validLink("https://github.com/PietroAlexandria"), true)
            compare(shortcuts.validLink("mailto:oi@exemplo.com"), true)
            compare(shortcuts.validLink("~/Documentos"), true)
            compare(shortcuts.validLink("/etc/hosts"), true)
            compare(shortcuts.validLink("rm -rf /"), false)
            compare(shortcuts.validLink("javascript:alert(1)"), false)
            compare(shortcuts.validLink("ftp://servidor"), false)
            compare(shortcuts.linkName("https://www.github.com/x/y?z=1"), "github.com")
            compare(shortcuts.linkName("/home/eu/Documentos/"), "Documentos")
            shortcuts.startAdding()
            shortcuts.mode = "link"
            const field = find(shortcuts, it => it.placeholderText !== undefined && it.placeholderText.indexOf("https://") === 0)
            verify(field)
            field.text = "https://exemplo.com/pagina"
            field.accepted()
            const list = JSON.parse(root.saved)
            compare(list.length, 1)
            compare(list[0].name, "exemplo.com")
            compare(list[0].icon, "internet-web-browser")
            // Texto inválido não cria atalho.
            shortcuts.startAdding(); shortcuts.mode = "link"; field.text = "rm -rf /"; field.accepted()
            compare(JSON.parse(root.saved).length, 1)
        }

        function test_atalhos_remover() {
            root.saved = JSON.stringify([{name: "A", target: "app:a", icon: "x"}, {name: "B", target: "app:b", icon: "x"}])
            wait(100)
            shortcuts.remove(0)
            compare(JSON.parse(root.saved).map(x => x.name), ["B"])
        }

        function test_audio_arrastar_volume_e_silenciar() {
            const bar = find(audio, it => it.moved !== undefined && it.value !== undefined && it.width > 100)
            verify(bar, "barra de volume")
            const p = bar.mapToItem(root, bar.width * 0.8, bar.height / 2)
            mousePress(root, p.x, p.y)
            mouseMove(root, p.x - bar.width * 0.3, p.y, 30)
            mouseRelease(root, p.x - bar.width * 0.3, p.y)
            verify(fake.calls.length >= 2, "pediu volume a cada movimento")
            verify(fake.calls[0].indexOf("volume 0.8") === 0, "primeiro toque: 80% — " + fake.calls[0])
            verify(fake.calls[fake.calls.length - 1].indexOf("volume 0.5") === 0, "termina perto de 50% — " + fake.calls[fake.calls.length - 1])
            fake.calls = []
            const mute = find(audio, it => it.tip === "Silenciar")
            verify(mute, "botão de silenciar")
            const m = mute.mapToItem(root, mute.width / 2, mute.height / 2)
            mouseClick(root, m.x, m.y)
            compare(fake.calls, ["mute true"])
        }

        function test_bluetooth_toque_conecta_e_desliga() {
            const row = find(bluetooth, it => it.modelData !== undefined && it.modelData.path === "/dev/2" && it.height === 34)
            verify(row, "linha do mouse")
            const p = row.mapToItem(root, row.width / 2, row.height / 2)
            mouseClick(root, p.x, p.y)
            compare(fake.calls, ["toggle /dev/2"])
            const power = find(bluetooth, it => it.tip === "Desligar o Bluetooth")
            verify(power)
            const q = power.mapToItem(root, power.width / 2, power.height / 2)
            mouseClick(root, q.x, q.y)
            compare(fake.calls[1], "bt false")
        }

        function test_consumidores_mede_so_enquanto_aparece() {
            compare(fake.acquired, 1)
            compare(top.rows.length, 2)
            top.tab = "memory"
            compare(top.rows.length, 1)
            compare(top.memoryText(1.5e9), "1,4 GB")
            compare(top.memoryText(5e7), "48 MB")
        }

        function test_launch_recusa_o_que_nao_e_app_link_ou_pasta() {
            compare(realSystem.launch("rm -rf /"), false)
            compare(realSystem.launch("app:../../bin/sh"), false)
            compare(realSystem.launch("app:a b"), false)
            compare(realSystem.launch("/caminho/que/nao/existe"), false)
            compare(realSystem.launch("ftp://servidor/arquivo"), false)
            compare(realSystem.launch("javascript:alert(1)"), false)
            compare(realSystem.launch(""), false)
        }
    }
}
