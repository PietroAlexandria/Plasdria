import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_showSystem: system.checked
    property alias cfg_showConnections: connections.checked
    property alias cfg_showMedia: media.checked
    property alias cfg_showNetwork: network.checked
    property alias cfg_showCalendar: calendar.checked
    property alias cfg_showReminders: reminders.checked
    property alias cfg_showNews: news.checked
    property alias cfg_showAudio: audio.checked
    property alias cfg_showBluetooth: bluetooth.checked
    property alias cfg_showTop: top.checked
    property alias cfg_showGpu: gpu.checked
    property alias cfg_showShortcuts: shortcuts.checked
    property alias cfg_showSpeedTest: speedtest.checked
    property alias cfg_showClock: clockCard.checked
    property alias cfg_showDay: dayCard.checked

    Kirigami.FormLayout {
        Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Cartões visíveis" }
        QQC2.CheckBox { id: weather; Kirigami.FormData.label: "Painel geral:"; text: "Horário, cidade, clima e previsões (sempre visível)"; checked: true; enabled: false }
        QQC2.CheckBox { id: system; Kirigami.FormData.label: "Cartões:"; text: "Sistema (uso, temperaturas e hardware)" }
        QQC2.CheckBox { id: connections; text: "Baterias e dispositivos" }
        QQC2.CheckBox { id: media; text: "Música tocando agora" }
        QQC2.CheckBox { id: network; text: "Rede e internet" }
        QQC2.CheckBox { id: calendar; text: "Calendário" }
        QQC2.CheckBox { id: reminders; text: "Lembretes" }
        QQC2.CheckBox { id: news; text: "Notícias" }
        QQC2.CheckBox { id: audio; text: "Áudio e brilho (volume, saída e brilho da tela)" }
        QQC2.CheckBox { id: bluetooth; text: "Bluetooth (dispositivos e bateria)" }
        QQC2.CheckBox { id: top; text: "Maiores consumidores (CPU e memória)" }
        QQC2.CheckBox { id: gpu; text: "GPU (uso, frequência e memória)" }
        QQC2.CheckBox { id: shortcuts; text: "Atalhos (aplicativos, sites e pastas)" }
        QQC2.CheckBox { id: speedtest; text: "Teste de velocidade da internet" }
        QQC2.CheckBox { id: clockCard; text: "Cronômetro, timer e pomodoro" }
        QQC2.CheckBox { id: dayCard; text: "Resumo do dia" }
        QQC2.Label {
            text: "O chat fica sempre visível. Os cartões novos (áudio, Bluetooth, consumidores, GPU, atalhos e teste de velocidade) começam ocultos no layout: use ✎ Editar e toque em ＋ para colocá-los onde quiser."
            wrapMode: Text.Wrap; opacity: 0.7
            Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        }
    }
}
