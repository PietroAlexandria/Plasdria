import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page
    property alias cfg_userName: userName.text
    property alias cfg_autoLocation: autoLocation.checked
    property string cfg_cityName
    property real cfg_cityLatitude
    property real cfg_cityLongitude
    property string cfg_defaultProvider
    property string cfg_defaultModel
    property string cfg_defaultEffort
    property alias cfg_customApiUrl: customApiUrl.text
    property alias cfg_customApiKey: customApiKey.text
    property alias cfg_customModel: customModel.text
    property string cfg_newsTopic
    property alias cfg_calendarUrls: calendarUrls.text
    property alias cfg_alertsEnabled: alertsOn.checked
    property alias cfg_alertBattery: alertBattery.value
    property alias cfg_alertDisk: alertDisk.value
    property alias cfg_alertTemp: alertTemp.value
    property alias cfg_alertOffline: alertOffline.value
    property alias cfg_pomodoroFocus: pomFocus.value
    property alias cfg_pomodoroShort: pomShort.value
    property alias cfg_pomodoroLong: pomLong.value
    property bool cfg_customApiKeyInVault
    property bool cfg_calendarUrlsInVault
    property alias cfg_eventLeadMinutes: eventLead.value

    property var results: []
    property string searchError: ""
    property bool searching: false

    readonly property var providerOptions: [
        {value: "antigravity", text: "Antigravity — Google DeepMind (agy)"},
        {value: "claude", text: "Claude — Anthropic (claude)"},
        {value: "codex", text: "Codex — OpenAI (codex)"},
        {value: "gemini", text: "Gemini CLI — Google (gemini)"},
        {value: "ollama", text: "Ollama — modelos locais (localhost:11434)"},
        {value: "custom", text: "API Compatível — OpenAI / OpenRouter / Groq / LM Studio"}
    ]
    readonly property var providerModelMap: ({
        antigravity: [
            {value: "gemini-4-argon", text: "Gemini 4 Argon — mais inteligente (recomendado)"},
            {value: "gemini-3.8-flash", text: "Gemini 3.8 Flash — mais rápido"},
            {value: "claude-opus-5-5", text: "Claude Opus 5.5 (Thinking)"},
            {value: "claude-sonnet-5-5", text: "Claude Sonnet 5.5"},
            {value: "gpt-oss-120b", text: "GPT-OSS 120B"}
        ],
        claude: [
            {value: "sonnet", text: "Sonnet — equilibrado (recomendado)"},
            {value: "opus", text: "Opus — mais inteligente"},
            {value: "fable", text: "Fable — tarefas mais difíceis"},
            {value: "haiku", text: "Haiku — mais rápido"}
        ],
        codex: [
            {value: "gpt-5.4", text: "GPT-5.4 — principal (recomendado)"},
            {value: "gpt-5.3-codex", text: "GPT-5.3 Codex — especializado em código"},
            {value: "o4-mini", text: "o4-mini — raciocínio rápido"}
        ],
        gemini: [
            {value: "gemini-2.5-pro", text: "Gemini 2.5 Pro — mais inteligente"},
            {value: "gemini-2.5-flash", text: "Gemini 2.5 Flash — mais rápido"}
        ],
        ollama: [
            {value: "llama3.2", text: "Llama 3.2 (detectado automaticamente no chat)"},
            {value: "qwen2.5-coder", text: "Qwen 2.5 Coder"},
            {value: "deepseek-r1", text: "DeepSeek R1"}
        ],
        custom: [
            {value: "gpt-4o", text: "GPT-4o"},
            {value: "gpt-4o-mini", text: "GPT-4o mini"},
            {value: "claude-3.7-sonnet", text: "Claude 3.7 Sonnet (OpenRouter)"},
            {value: "deepseek-chat", text: "DeepSeek V3"}
        ]
    })
    readonly property var modelOptions: providerModelMap[page.cfg_defaultProvider] || providerModelMap.claude
    readonly property var effortOptions: [
        {value: "low", text: "Baixo"}, {value: "medium", text: "Médio"}, {value: "high", text: "Alto"},
        {value: "xhigh", text: "Extra alto"}, {value: "max", text: "Máximo"}
    ]
    readonly property var topicOptions: [
        {value: "", text: "Principais"}, {value: "NATION", text: "Brasil"}, {value: "WORLD", text: "Mundo"},
        {value: "TECHNOLOGY", text: "Tecnologia"}, {value: "BUSINESS", text: "Economia"}, {value: "SPORTS", text: "Esportes"},
        {value: "ENTERTAINMENT", text: "Entretenimento"}, {value: "SCIENCE", text: "Ciência"}, {value: "HEALTH", text: "Saúde"}
    ]
    function indexOf(list, value) { for (let i = 0; i < list.length; ++i) if (list[i].value === value) return i; return 0 }

    function search() {
        const query = cityField.text.trim()
        if (query.length < 2) return
        searching = true; searchError = ""; results = []
        const request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE) return
            searching = false
            if (request.status !== 200) { searchError = "Não foi possível buscar agora. Verifique a internet."; return }
            try {
                const found = JSON.parse(request.responseText).results || []
                results = found
                if (!found.length) searchError = "Nenhuma cidade encontrada."
            } catch (e) { searchError = "Resposta inválida do serviço de busca." }
        }
        request.open("GET", "https://geocoding-api.open-meteo.com/v1/search?count=6&language=pt&name=" + encodeURIComponent(query))
        request.send()
    }

    Kirigami.FormLayout {
        QQC2.TextField {
            id: userName
            Kirigami.FormData.label: "Seu nome:"
            placeholderText: "Usado na saudação (opcional)"
        }

        Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Clima" }

        QQC2.CheckBox {
            id: autoLocation
            Kirigami.FormData.label: "Localização:"
            text: "Detectar automaticamente pela rede"
        }
        QQC2.Label {
            Kirigami.FormData.label: "Cidade atual:"
            text: page.cfg_cityName + "  (" + page.cfg_cityLatitude.toFixed(2) + ", " + page.cfg_cityLongitude.toFixed(2) + ")"
            enabled: !autoLocation.checked
        }
        RowLayout {
            Kirigami.FormData.label: "Trocar cidade:"
            enabled: !autoLocation.checked
            QQC2.TextField {
                id: cityField
                placeholderText: "Digite o nome da cidade"
                Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                onAccepted: page.search()
            }
            QQC2.Button { text: "Buscar"; icon.name: "search"; enabled: !page.searching; onClicked: page.search() }
            QQC2.BusyIndicator { running: page.searching; visible: running; Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5 }
        }
        ColumnLayout {
            visible: page.results.length > 0 || page.searchError !== ""
            enabled: !autoLocation.checked
            Layout.preferredWidth: Kirigami.Units.gridUnit * 22
            QQC2.Label { visible: page.searchError !== ""; text: page.searchError; color: Kirigami.Theme.negativeTextColor }
            Repeater {
                model: page.results
                delegate: QQC2.ItemDelegate {
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData.name + " — " + [modelData.admin1, modelData.country].filter(Boolean).join(", ")
                    icon.name: "mark-location"
                    onClicked: {
                        page.cfg_cityName = modelData.name
                        page.cfg_cityLatitude = modelData.latitude
                        page.cfg_cityLongitude = modelData.longitude
                        page.results = []; cityField.text = ""
                    }
                }
            }
        }

        Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Assistente de IA" }

        QQC2.ComboBox {
            Kirigami.FormData.label: "IA padrão:"
            model: page.providerOptions; textRole: "text"; valueRole: "value"
            currentIndex: page.indexOf(page.providerOptions, page.cfg_defaultProvider || "antigravity")
            onActivated: {
                page.cfg_defaultProvider = currentValue
                const list = page.providerModelMap[currentValue] || []
                if (list.length > 0) page.cfg_defaultModel = list[0].value
            }
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: "Modelo padrão:"
            model: page.modelOptions; textRole: "text"; valueRole: "value"
            currentIndex: page.indexOf(page.modelOptions, page.cfg_defaultModel)
            onActivated: page.cfg_defaultModel = currentValue
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: "Esforço padrão:"
            visible: page.cfg_defaultProvider === "antigravity" || page.cfg_defaultProvider === "claude" || page.cfg_defaultProvider === "codex"
            model: page.effortOptions; textRole: "text"; valueRole: "value"
            currentIndex: page.indexOf(page.effortOptions, page.cfg_defaultEffort)
            onActivated: page.cfg_defaultEffort = currentValue
        }
        QQC2.TextField {
            id: customApiUrl
            visible: page.cfg_defaultProvider === "custom"
            Kirigami.FormData.label: "Endpoint da API:"
            placeholderText: "https://api.openai.com/v1"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        }
        QQC2.TextField {
            id: customApiKey
            visible: page.cfg_defaultProvider === "custom"
            Kirigami.FormData.label: "Chave da API:"
            placeholderText: page.cfg_customApiKeyInVault ? "Guardada no cofre do sistema. Digite para trocar (“-” apaga)." : "sk-... (ou defina OPENAI_API_KEY)"
            echoMode: TextInput.Password
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        }
        QQC2.TextField {
            id: customModel
            visible: page.cfg_defaultProvider === "custom"
            Kirigami.FormData.label: "ID do modelo (opcional):"
            placeholderText: "Ex.: anthropic/claude-3.7-sonnet, llama-3.3-70b-versatile"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        }
        QQC2.Label {
            text: "Você pode alternar entre Antigravity, Claude e outras IAs diretamente no cabeçalho do chat ou com /ia."
            wrapMode: Text.Wrap; opacity: 0.7
            Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        }

        Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Notícias" }

        QQC2.ComboBox {
            Kirigami.FormData.label: "Tema:"
            model: page.topicOptions; textRole: "text"; valueRole: "value"
            currentIndex: page.indexOf(page.topicOptions, page.cfg_newsTopic)
            onActivated: page.cfg_newsTopic = currentValue
        }

        Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Agenda" }

        QQC2.TextArea {
            id: calendarUrls
            Kirigami.FormData.label: "Links iCal (.ics):"
            placeholderText: page.cfg_calendarUrlsInVault ? "Guardados no cofre do sistema. Digite para substituir (“-” apaga)." : "https://calendar.google.com/calendar/ical/.../basic.ics"
            wrapMode: TextEdit.NoWrap
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
            Layout.preferredHeight: Kirigami.Units.gridUnit * 4
        }
        QQC2.SpinBox {
            id: eventLead
            Kirigami.FormData.label: "Avisar antes do evento:"
            from: 0; to: 120; stepSize: 5
            textFromValue: v => v === 0 ? "desligado" : v + " min"
            valueFromText: t => parseInt(t) || 0
        }
        QQC2.Label {
            text: "Um link por linha. No Google Agenda: Configurações da agenda → “Endereço secreto no formato iCal”. Esse endereço dá acesso à sua agenda: não o compartilhe. Os eventos aparecem no calendário e atualizam a cada 15 minutos."
            wrapMode: Text.Wrap; opacity: 0.7
            Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        }

        Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Pomodoro" }

        QQC2.SpinBox { id: pomFocus; Kirigami.FormData.label: "Foco:"; from: 1; to: 180; textFromValue: v => v + " min"; valueFromText: t => parseInt(t) || 25 }
        QQC2.SpinBox { id: pomShort; Kirigami.FormData.label: "Pausa curta:"; from: 1; to: 60; textFromValue: v => v + " min"; valueFromText: t => parseInt(t) || 5 }
        QQC2.SpinBox { id: pomLong; Kirigami.FormData.label: "Pausa longa:"; from: 1; to: 120; textFromValue: v => v + " min"; valueFromText: t => parseInt(t) || 15 }
        QQC2.Label {
            text: "A pausa longa vem depois de 4 focos. Os avisos aparecem como notificações do sistema, mesmo com o painel fechado."
            wrapMode: Text.Wrap; opacity: 0.7
            Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        }

        Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Alertas do sistema" }

        QQC2.CheckBox { id: alertsOn; Kirigami.FormData.label: "Avisos:"; text: "Notificar quando algo precisar de atenção" }
        QQC2.SpinBox { id: alertBattery; enabled: alertsOn.checked; Kirigami.FormData.label: "Bateria baixa:"; from: 0; to: 50; textFromValue: v => v === 0 ? "desligado" : v + "%"; valueFromText: t => parseInt(t) || 0 }
        QQC2.SpinBox { id: alertDisk; enabled: alertsOn.checked; Kirigami.FormData.label: "Disco cheio:"; from: 0; to: 100; textFromValue: v => v === 0 ? "desligado" : v + "%"; valueFromText: t => parseInt(t) || 0 }
        QQC2.SpinBox { id: alertTemp; enabled: alertsOn.checked; Kirigami.FormData.label: "CPU quente:"; from: 0; to: 110; textFromValue: v => v === 0 ? "desligado" : v + " °C"; valueFromText: t => parseInt(t) || 0 }
        QQC2.SpinBox { id: alertOffline; enabled: alertsOn.checked; Kirigami.FormData.label: "Sem internet:"; from: 0; to: 600; stepSize: 15; textFromValue: v => v === 0 ? "desligado" : "após " + v + " s"; valueFromText: t => parseInt(t) || 0 }
        QQC2.Label {
            text: "Cada aviso aparece uma vez e só volta depois que o valor se recupera. Funcionam com o painel fechado. A temperatura depende do sensor do seu computador."
            wrapMode: Text.Wrap; opacity: 0.7
            Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        }
    }
}
