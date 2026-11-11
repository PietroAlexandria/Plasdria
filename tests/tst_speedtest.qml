import QtQuick
import QtTest
import "../package/contents/ui/bridge" as Backend

// Teste de velocidade contra um servidor local de mentira (tests/fake_speed_server.py, porta 18766).
// O run.sh aponta XDG_DATA_HOME para uma pasta temporária: o histórico real do usuário não é tocado.
Item {
    width: 100; height: 100
    Backend.SpeedTestClient { id: speed; baseUrl: "http://127.0.0.1:18766"; testSeconds: 1.5; streams: 3 }
    SignalSpy { id: finished; target: speed; signalName: "finished" }

    TestCase {
        name: "TesteDeVelocidade"
        when: windowShown

        function init() { finished.clear(); speed.baseUrl = "http://127.0.0.1:18766" }

        function test_medicao_completa() {
            const before = speed.history.length
            speed.start()
            verify(speed.running)
            compare(speed.phase, "ping")
            tryVerify(() => !speed.running, 20000)
            compare(finished.count, 1)
            verify(finished.signalArguments[0][0] === true, "o teste falhou: " + speed.error)
            compare(speed.error, "")
            compare(speed.progress, 1)
            verify(speed.pingMs >= 0 && speed.pingMs < 500, "ping " + speed.pingMs)
            verify(speed.jitterMs >= 0, "jitter " + speed.jitterMs)
            verify(speed.downloadMbps > 1, "download " + speed.downloadMbps)
            verify(speed.uploadMbps > 1, "upload " + speed.uploadMbps)
            compare(speed.server, "127.0.0.1")
            compare(speed.history.length, before + 1)
            const last = speed.history[0]
            verify(Math.abs(last.down - speed.downloadMbps) < 0.001)
            verify(last.time > 1.7e9)
        }

        function test_cancelar_no_meio() {
            const before = speed.history.length
            speed.start()
            tryVerify(() => speed.phase === "download", 10000)
            speed.cancel()
            verify(!speed.running)
            compare(speed.phase, "")
            compare(speed.progress, 0)
            compare(speed.downloadMbps, -1)
            compare(speed.history.length, before)   // teste cancelado não entra no histórico
            wait(300)                               // respostas atrasadas não podem reviver o teste
            verify(!speed.running)
            compare(speed.history.length, before)
        }

        function test_servidor_fora_do_ar() {
            speed.baseUrl = "http://127.0.0.1:1"
            const before = speed.history.length
            speed.start()
            tryVerify(() => !speed.running, 10000)
            compare(finished.signalArguments[0][0], false)
            compare(speed.error, "Sem conexão com o servidor de teste.")
            compare(speed.history.length, before)
        }

        function test_nao_inicia_duas_vezes_e_limpa_historico() {
            speed.start()
            speed.start()
            speed.cancel()
            speed.clearHistory()
            compare(speed.history.length, 0)
        }
    }
}
