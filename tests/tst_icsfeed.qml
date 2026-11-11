import QtQuick
import QtTest
import "../package/contents/ui"

// Baixa uma agenda iCal de um servidor local (iniciado por tests/run.sh na porta 18765) e
// confere eventos com repetição, o aviso de falta de conexão e a mistura de várias agendas.
Item {
    width: 200; height: 200
    IcsFeed { id: feed }
    TestCase {
        name: "AgendaIcal"
        when: windowShown

        function test_baixa_e_expande_repeticoes() {
            feed.urls = "http://127.0.0.1:18765/agenda.ics"
            verify(feed.configured)
            tryVerify(() => feed.events.length > 20, 5000)
            const standups = feed.events.filter(e => e.title === "Standup diário")
            verify(standups.length >= 60, "um standup por dia nos próximos ~70 dias: " + standups.length)
            const weekly = feed.events.filter(e => e.title === "Reunião, semanal")
            verify(weekly.length >= 8 && weekly.length <= 11, "reuniões semanais: " + weekly.length)
            compare(weekly[0].location, "Sala 3")
            compare(new Date(weekly[0].start).getDay(), 1)   // segunda-feira
            for (let i = 1; i < feed.events.length; ++i) verify(feed.events[i - 1].start <= feed.events[i].start, "em ordem")
            compare(feed.status, "")
        }

        function test_sem_conexao_mantem_o_que_ja_baixou() {
            feed.urls = "http://127.0.0.1:18765/agenda.ics"
            tryVerify(() => feed.events.length > 20, 5000)
            const before = feed.events.length
            feed.urls = "http://127.0.0.1:18765/agenda.ics\nhttp://127.0.0.1:1/fora.ics"
            tryVerify(() => feed.status !== "", 5000)
            compare(feed.status, "Sem conexão com a agenda.")
            compare(feed.events.length, before)     // continua mostrando a agenda que funcionou
        }

        function test_links_invalidos_sao_ignorados() {
            feed.urls = "file:///etc/passwd\njavascript:alert(1)\n   \nwebcal://127.0.0.1:18765/agenda.ics"
            compare(feed.list, ["https://127.0.0.1:18765/agenda.ics"])   // só http(s); webcal vira https
        }
    }
}
