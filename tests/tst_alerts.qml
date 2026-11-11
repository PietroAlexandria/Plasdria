import QtQuick
import QtTest
import "../package/contents/ui"

// Alertas do sistema: dispara uma vez, rearma ao se recuperar, respeita limites e a opção de desligar.
Item {
    id: root
    width: 100; height: 100
    property var notices: []
    readonly property real t0: new Date(2026, 5, 10, 8, 0, 0).getTime()
    AlertEngine {
        id: a
        fakeNow: root.t0
        onNotify: (title, body) => root.notices.push(title)
    }
    TestCase {
        name: "Alertas"
        when: windowShown
        function init() {
            a.enabled = true; a.batteryLow = 20; a.diskFull = 90; a.tempHigh = 85; a.offlineSeconds = 45
            a.battery = 80; a.charging = false; a.disk = 40; a.temp = 50; a.online = true
            a.fired = ({}); a.offlineSince = 0; a.fakeNow = root.t0
            root.notices = []
        }
        function test_nada_acontece_com_tudo_normal() { a.check(); compare(root.notices.length, 0) }
        function test_bateria_baixa_avisa_uma_vez_e_rearma() {
            a.battery = 18; a.check(); a.check()
            compare(root.notices, ["Bateria baixa"])
            a.battery = 22; a.check(); a.battery = 15; a.check()
            compare(root.notices.length, 1, "22% ainda não rearmou (precisa passar de 25)")
            a.battery = 30; a.check(); a.battery = 15; a.check()
            compare(root.notices.length, 2)
        }
        function test_bateria_na_tomada_nao_avisa() {
            a.battery = 10; a.charging = true; a.check()
            compare(root.notices.length, 0)
            a.charging = false; a.check(); compare(root.notices, ["Bateria baixa"])
            a.charging = true; a.check(); a.charging = false; a.check()
            compare(root.notices.length, 2, "ligar na tomada rearma")
        }
        function test_sem_bateria_ou_sensor_nao_avisa() {
            a.battery = -1; a.temp = -1; a.disk = -1; a.check()
            compare(root.notices.length, 0)
        }
        function test_disco_e_temperatura() {
            a.disk = 93; a.temp = 90; a.check(); a.check()
            compare(root.notices, ["Disco quase cheio", "CPU muito quente"])
            a.disk = 89; a.temp = 82; a.check(); a.disk = 95; a.temp = 95; a.check()
            compare(root.notices.length, 2, "dentro da folga de histerese não repete")
            a.disk = 80; a.temp = 60; a.check(); a.disk = 95; a.temp = 95; a.check()
            compare(root.notices.length, 4)
        }
        function test_internet_so_avisa_depois_do_tempo_e_avisa_a_volta() {
            a.online = false; a.check()
            a.fakeNow += 30000; a.check()
            compare(root.notices.length, 0, "ainda dentro dos 45 s")
            a.fakeNow += 20000; a.check()
            compare(root.notices, ["Sem internet"])
            a.fakeNow += 60000; a.check()
            compare(root.notices.length, 1, "avisa uma vez só")
            a.online = true; a.check()
            compare(root.notices, ["Sem internet", "Internet de volta"])
        }
        function test_queda_curta_nao_avisa_nem_diz_que_voltou() {
            a.online = false; a.check(); a.fakeNow += 10000; a.online = true; a.check()
            compare(root.notices.length, 0)
            a.fakeNow += 100000; a.online = false; a.check(); a.fakeNow += 20000; a.check()
            compare(root.notices.length, 0, "a contagem recomeça a cada queda")
        }
        function test_limite_zero_desliga_e_enabled_falso_silencia_tudo() {
            a.batteryLow = 0; a.battery = 5; a.check()
            compare(root.notices.length, 0)
            a.batteryLow = 20; a.enabled = false; a.check()
            compare(root.notices.length, 0)
        }
    }
}
