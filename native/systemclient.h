#pragma once

#include <QHash>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariantList>
#include <functional>

// Controles e leituras do sistema para os cartões de áudio/brilho, Bluetooth, processos, GPU e atalhos.
//  - Áudio: PipeWire/PulseAudio via `pactl`.
//  - Brilho: leitura em /sys/class/backlight; escrita pelo logind (sem root).
//  - Bluetooth: BlueZ pelo D-Bus do sistema (e rfkill para ligar).
//  - Processos: /proc, agrupados por nome.
//  - GPU: sysfs (Intel i915 por RC6, AMD amdgpu) — NVIDIA continua no DashboardClient.
//  - Atalhos: lista de aplicativos instalados (.desktop) e abertura de app, link ou pasta.
class SystemClient : public QObject {
    Q_OBJECT
    // Áudio
    Q_PROPERTY(bool audioAvailable READ audioAvailable NOTIFY audioChanged)
    Q_PROPERTY(double audioVolume READ audioVolume NOTIFY audioChanged)       // 0..1 (pode passar de 1)
    Q_PROPERTY(bool audioMuted READ audioMuted NOTIFY audioChanged)
    Q_PROPERTY(QString audioSink READ audioSink NOTIFY audioChanged)          // id da saída padrão
    Q_PROPERTY(QVariantList audioSinks READ audioSinks NOTIFY audioChanged)   // [{id, name}]
    // Brilho
    Q_PROPERTY(bool brightnessAvailable READ brightnessAvailable NOTIFY brightnessChanged)
    Q_PROPERTY(double brightness READ brightness NOTIFY brightnessChanged)    // 0..1
    // Bluetooth
    Q_PROPERTY(bool bluetoothAvailable READ bluetoothAvailable NOTIFY bluetoothChanged)
    Q_PROPERTY(bool bluetoothPowered READ bluetoothPowered NOTIFY bluetoothChanged)
    Q_PROPERTY(bool bluetoothBlocked READ bluetoothBlocked NOTIFY bluetoothChanged)
    Q_PROPERTY(QVariantList bluetoothDevices READ bluetoothDevices NOTIFY bluetoothChanged) // [{path, name, icon, connected, battery}]
    // Processos
    Q_PROPERTY(bool topActive READ topActive NOTIFY topChanged)
    Q_PROPERTY(QVariantList topCpu READ topCpu NOTIFY topChanged)             // [{name, cpu, memory, count}]
    Q_PROPERTY(QVariantList topMemory READ topMemory NOTIFY topChanged)
    // GPU
    Q_PROPERTY(QString gpuName READ gpuName NOTIFY gpuChanged)
    Q_PROPERTY(QString gpuDriver READ gpuDriver NOTIFY gpuChanged)
    Q_PROPERTY(double gpuUsage READ gpuUsage NOTIFY gpuChanged)               // %, -1 se desconhecido
    Q_PROPERTY(double gpuFrequency READ gpuFrequency NOTIFY gpuChanged)       // MHz, -1
    Q_PROPERTY(double gpuFrequencyMax READ gpuFrequencyMax NOTIFY gpuChanged)
    Q_PROPERTY(double gpuTemperature READ gpuTemperature NOTIFY gpuChanged)   // °C, -1
    Q_PROPERTY(double gpuMemoryUsed READ gpuMemoryUsed NOTIFY gpuChanged)     // bytes, -1
    Q_PROPERTY(double gpuMemoryTotal READ gpuMemoryTotal NOTIFY gpuChanged)
    Q_PROPERTY(QVariantList gpuHistory READ gpuHistory NOTIFY gpuChanged)     // últimas amostras de uso (%)
    // false (ex.: painel recolhido) pausa todas as leituras; elas voltam sozinhas quando fica true.
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
public:
    explicit SystemClient(QObject *parent = nullptr);
    ~SystemClient() override;

    bool active() const { return m_active; }
    void setActive(bool on);
    // Quem mostra dados avisa que precisa deles: "audio", "brightness", "bluetooth", "gpu" ou "top".
    // As leituras só rodam enquanto houver pelo menos um interessado (recriar um cartão adquire o novo
    // antes de liberar o antigo, então nunca chega a zero).
    Q_INVOKABLE void acquire(const QString &topic);
    Q_INVOKABLE void release(const QString &topic);

    bool audioAvailable() const { return m_audioAvailable; }
    double audioVolume() const { return m_audioVolume; }
    bool audioMuted() const { return m_audioMuted; }
    QString audioSink() const { return m_audioSink; }
    QVariantList audioSinks() const { return m_audioSinks; }
    bool brightnessAvailable() const { return !m_backlight.isEmpty() && m_brightnessMax > 0; }
    double brightness() const { return m_brightnessMax > 0 ? double(m_brightnessValue) / m_brightnessMax : 0; }
    bool bluetoothAvailable() const { return m_btAvailable; }
    bool bluetoothPowered() const { return m_btPowered; }
    bool bluetoothBlocked() const { return m_btBlocked; }
    QVariantList bluetoothDevices() const { return m_btDevices; }
    bool topActive() const { return m_topActive; }
    // Quem mostra a lista chama acquireTop/releaseTop: a medição roda enquanto houver pelo menos um interessado
    // (recriar o cartão libera o antigo depois de adquirir o novo, então um simples liga/desliga falharia).
    Q_INVOKABLE void acquireTop();
    Q_INVOKABLE void releaseTop();
    QVariantList topCpu() const { return m_topCpu; }
    QVariantList topMemory() const { return m_topMemory; }
    QString gpuName() const { return m_gpuName; }
    QString gpuDriver() const { return m_gpuDriver; }
    double gpuUsage() const { return m_gpuUsage; }
    double gpuFrequency() const { return m_gpuFreq; }
    double gpuFrequencyMax() const { return m_gpuFreqMax; }
    double gpuTemperature() const { return m_gpuTemp; }
    double gpuMemoryUsed() const { return m_gpuMemUsed; }
    double gpuMemoryTotal() const { return m_gpuMemTotal; }
    QVariantList gpuHistory() const { return m_gpuHistory; }

    Q_INVOKABLE void setAudioVolume(double volume);
    Q_INVOKABLE void setAudioMuted(bool muted);
    Q_INVOKABLE void setAudioSink(const QString &id);
    Q_INVOKABLE void setBrightness(double value);
    Q_INVOKABLE void setBluetoothPowered(bool on);
    Q_INVOKABLE void toggleBluetoothDevice(const QString &path);
    // Aplicativos instalados: [{id, name, icon}] em ordem alfabética.
    Q_INVOKABLE QVariantList applications();
    // "app:<id-do-.desktop>", endereço (http/https/mailto) ou caminho de arquivo/pasta.
    Q_INVOKABLE bool launch(const QString &target);

signals:
    void activeChanged();
    void audioChanged();
    void brightnessChanged();
    void bluetoothChanged();
    void topChanged();
    void gpuChanged();

private:
    void apply(const QString &topic);
    void startAudioEvents();
    void stopAudioEvents();
    void pollAudio();
    void pollBrightness();
    void pollBluetooth();
    void sampleProcesses();
    void sampleGpu();
    void findBacklight();
    void findGpu();
    void run(const QStringList &args, std::function<void(const QByteArray &)> done = {});

    bool m_active = true;
    QHash<QString, int> m_users;
    QProcess *m_audioEvents = nullptr;
    QTimer m_audioDebounce;
    bool m_audioDirty = false;
    QTimer m_audioTimer, m_brightnessTimer, m_btTimer, m_topTimer, m_gpuTimer, m_applyAudio, m_applyBrightness;
    // áudio
    bool m_audioAvailable = false, m_audioMuted = false, m_audioBusy = false;
    double m_audioVolume = 0, m_pendingVolume = -1;
    QString m_audioSink;
    QVariantList m_audioSinks;
    // brilho
    QString m_backlight;
    int m_brightnessValue = 0, m_brightnessMax = 0, m_pendingBrightness = -1;
    // bluetooth
    bool m_btAvailable = false, m_btPowered = false, m_btBlocked = false, m_btBusy = false;
    QString m_btAdapter;
    QVariantList m_btDevices;
    // processos
    bool m_topActive = false;
    int m_topUsers = 0;
    QVariantList m_topCpu, m_topMemory;
    QHash<qint64, qint64> m_prevJiffies;
    qint64 m_prevTopAt = 0;
    // GPU
    bool m_gpuLoaded = false;
    QString m_gpuName, m_gpuDriver, m_gpuDir;
    double m_gpuUsage = -1, m_gpuFreq = -1, m_gpuFreqMax = -1, m_gpuTemp = -1, m_gpuMemUsed = -1, m_gpuMemTotal = -1;
    qint64 m_prevRc6 = -1, m_prevRc6At = 0;
    QVariantList m_gpuHistory;
    // aplicativos
    QVariantList m_apps;
};
