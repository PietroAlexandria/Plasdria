import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "bridge" as Backend
import "timeparse.js" as TP

PlasmoidItem {
    id: root
    readonly property var cfg: Plasmoid.configuration
    readonly property bool onDesktop: Plasmoid.formFactor === PlasmaCore.Types.Planar
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: onDesktop ? fullRepresentation : compactRepresentation
    switchWidth: 340; switchHeight: 420
    property bool layoutEditing: false

    toolTipMainText: "Plasdria"
    toolTipSubText: {
        const used = claudeBackend.fiveHourUsed
        return claudeBackend.providerName + " · " + claudeBackend.status + (used >= 0 ? " · " + Math.round(100 - used) + "% da cota de 5h livre" : "")
    }

    Theme {
        id: themeBackend
        accentBase: root.cfg.accentColor || "#3daee9"
        backgroundOpacity: (root.cfg.backgroundOpacity || 94) / 100
        animations: root.cfg.animations
        mode: root.cfg.themeMode || "dark"
        systemDark: Kirigami.Theme.backgroundColor.hslLightness < 0.5
    }

    // Segredos (chave da API e link da agenda) ficam no cofre do sistema, não no arquivo de configuração
    // do Plasma (que qualquer usuário do computador lê). Sem cofre disponível, continuam na configuração.
    property string secretApiKey: ""
    property string secretCalendarUrls: ""
    readonly property string cfgApiKey: cfg.customApiKey || ""
    readonly property string cfgCalendarUrls: cfg.calendarUrls || ""
    readonly property string effectiveApiKey: cfgApiKey.trim() !== "" ? cfgApiKey : secretApiKey
    readonly property string effectiveCalendarUrls: cfgCalendarUrls.trim() !== "" ? cfgCalendarUrls : secretCalendarUrls
    // O que for digitado nas configurações passa para o cofre e o campo é esvaziado. Escrever "-" apaga.
    function moveToVault(name, typed) {
        const value = typed.trim() === "-" ? "" : typed.trim()
        return vault.write(name, value) ? value : null
    }
    function migrateSecrets() {
        if (cfgApiKey.trim() !== "") {
            const v = moveToVault("customApiKey", cfgApiKey)
            if (v !== null) { secretApiKey = v; cfg.customApiKeyInVault = v !== ""; cfg.customApiKey = "" }
        }
        if (cfgCalendarUrls.trim() !== "") {
            const v = moveToVault("calendarUrls", cfgCalendarUrls)
            if (v !== null) { secretCalendarUrls = v; cfg.calendarUrlsInVault = v !== ""; cfg.calendarUrls = "" }
        }
    }
    onCfgApiKeyChanged: migrateSecrets()
    onCfgCalendarUrlsChanged: migrateSecrets()
    Backend.SecretClient {
        id: vault
        // Lido antes de o chat conectar (objetos completam na ordem em que aparecem neste arquivo).
        Component.onCompleted: {
            root.secretApiKey = read("customApiKey")
            root.secretCalendarUrls = read("calendarUrls")
            root.migrateSecrets()
        }
    }

    Backend.ClaudeClient {
        id: claudeBackend
        property bool defaultsApplied: false
        customApiUrl: root.cfg.customApiUrl || "https://api.openai.com/v1"
        customApiKey: root.effectiveApiKey
        customModel: root.cfg.customModel || ""
        Component.onCompleted: {
            if (!hasSavedProvider && root.cfg.defaultProvider) provider = root.cfg.defaultProvider
            start()
        }
        onChanged: {
            // Modelo e esforço das configurações valem ao iniciar; trocas no chat valem até reiniciar.
            if (defaultsApplied || !ready) return
            defaultsApplied = true
            root.applyModelDefaults()
        }
    }
    function applyModelDefaults() {
        if (claudeBackend.models.some(m => m.id === cfg.defaultModel)) claudeBackend.model = cfg.defaultModel
        if (claudeBackend.efforts.indexOf(cfg.defaultEffort) >= 0) claudeBackend.effort = cfg.defaultEffort
    }

    Backend.DashboardClient {
        id: dashBackend
        Component.onCompleted: { root.applyLocation(); setNewsTopic(root.cfg.newsTopic || ""); start() }
    }
    function applyLocation() {
        if (cfg.autoLocation) dashBackend.setLocation("", 0, 0)
        else dashBackend.setLocation(cfg.cityName, cfg.cityLatitude, cfg.cityLongitude)
    }
    readonly property string locationKey: [cfg.autoLocation, cfg.cityName, cfg.cityLatitude, cfg.cityLongitude].join("|")
    onLocationKeyChanged: applyLocation()
    readonly property string newsTopic: cfg.newsTopic || ""
    onNewsTopicChanged: dashBackend.setNewsTopic(newsTopic)
    readonly property string defaultProviderCfg: cfg.defaultProvider || "antigravity"
    onDefaultProviderCfgChanged: if (!claudeBackend.busy) claudeBackend.provider = defaultProviderCfg
    readonly property string modelKey: cfg.defaultModel + "|" + cfg.defaultEffort
    onModelKeyChanged: if (claudeBackend.ready && !claudeBackend.busy) applyModelDefaults()

    // Alarmes dos lembretes: avisa uma vez quando chega a hora (mesmo com o painel fechado).
    Timer {
        interval: 15000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.checkReminders()
    }
    function checkReminders() {
        let list
        try { list = JSON.parse(cfg.reminders || "[]") } catch (e) { return }
        if (!Array.isArray(list)) return
        const result = TP.dueReminders(list, Date.now())
        for (const text of result.notify) dashBackend.notify("Lembrete", text)
        if (result.changed) cfg.reminders = JSON.stringify(result.list)
        checkEvents()
    }
    // Eventos da agenda: avisa alguns minutos antes (0 desliga). O que já foi avisado fica só em memória.
    property var notifiedEvents: ({})
    function checkEvents() {
        const lead = (cfg.eventLeadMinutes === undefined ? 10 : cfg.eventLeadMinutes) * 60000
        const result = TP.upcomingEvents(calendarFeed.events, Date.now(), lead, notifiedEvents)
        notifiedEvents = result.seen
        for (const e of result.notify)
            dashBackend.notify(e.title, "Começa em " + e.minutes + " min (" + new Date(e.start).toLocaleTimeString(Qt.locale(), "HH:mm") + ")" + (e.location ? " · " + e.location : ""))
    }

    IcsFeed { id: calendarFeed; urls: root.effectiveCalendarUrls }

    Backend.MediaClient { id: mediaBackend }
    // Com o painel recolhido (modo ícone), as leituras do sistema param.
    Backend.SystemClient { id: sysBackend; active: root.onDesktop || root.expanded }
    Backend.SpeedTestClient { id: speedBackend }
    // Cronômetro, timer e pomodoro: o motor fica aqui para os alarmes tocarem mesmo com o cartão oculto.
    ClockEngine {
        id: clockEngine
        focusMin: root.cfg.pomodoroFocus || 25
        shortMin: root.cfg.pomodoroShort || 5
        longMin: root.cfg.pomodoroLong || 15
        onNotify: (title, body) => dashBackend.notify(title, body)
        onPersist: json => root.cfg.clockState = json
        Component.onCompleted: load(root.cfg.clockState || "")
    }
    Backend.NetworkClient { id: netBackend }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: "Nova conversa"
            icon.name: "list-add"
            onTriggered: { claudeBackend.newChat(); root.expanded = true }
        },
        PlasmaCore.Action {
            text: "Alternar IA (" + claudeBackend.providerName + ")"
            icon.name: "Synchronize"
            onTriggered: { claudeBackend.nextProvider(); root.expanded = true }
        },
        PlasmaCore.Action {
            text: root.layoutEditing ? "Concluir a edição do layout" : "Editar layout"
            icon.name: "document-edit"
            onTriggered: { root.layoutEditing = !root.layoutEditing; root.expanded = true }
        },
        PlasmaCore.Action {
            text: "Reconectar ao " + claudeBackend.providerName
            icon.name: "view-refresh"
            onTriggered: claudeBackend.reconnect()
        }
    ]

    fullRepresentation: Shell {
        id: shell
        t: themeBackend; client: claudeBackend; dash: dashBackend; media: mediaBackend; net: netBackend; cfg: root.cfg
        editing: root.layoutEditing
        sys: sysBackend
        speed: speedBackend
        clock: clockEngine
        onSaveShortcuts: json => root.cfg.shortcuts = json
        onWelcomeDone: root.cfg.welcomeSeen = 1
        events: calendarFeed.events; feedConfigured: calendarFeed.configured; feedStatus: calendarFeed.status
        onEditRequested: on => root.layoutEditing = on
        onSaveReminders: json => root.cfg.reminders = json
        onSaveLayout: json => root.cfg.layout = json
        Layout.minimumWidth: 340
        Layout.minimumHeight: 480
        Layout.preferredWidth: 1280
        Layout.preferredHeight: 800
        Connections {
            target: root
            function onExpandedChanged() { if (root.expanded) shell.focusChat() }
        }
    }

    compactRepresentation: CompactIcon {
        t: themeBackend; client: claudeBackend
        onClicked: root.expanded = !root.expanded
    }
}
