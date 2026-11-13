#include "systemclient.h"

#include <QDateTime>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>
#include <QThread>
#include <QUrl>
#include <algorithm>
#include <unistd.h>

namespace {
QString readText(const QString &path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return {};
    return QString::fromUtf8(file.readAll()).trimmed();
}
double readNumber(const QString &path, double fallback = -1) {
    bool ok = false;
    const double value = readText(path).toDouble(&ok);
    return ok ? value : fallback;
}

// Nomes de processos filhos que o navegador troca por títulos próprios.
QString friendlyName(const QString &comm) {
    static const QSet<QString> firefox = {"Isolated Web Co", "Web Content", "WebExtensions", "RDD Process", "Privileged Cont",
                                          "Socket Process", "GPU Process", "Utility Process", "Isolated Servic", "Forking Server"};
    if (firefox.contains(comm)) return QStringLiteral("firefox");
    return comm;
}

struct DesktopEntry { QString id, name, icon; };

QString localized(const QMap<QString, QString> &fields, const QString &key) {
    const QString locale = QLocale::system().name();   // pt_BR
    for (const QString &candidate : {key + "[" + locale + "]", key + "[" + locale.section('_', 0, 0) + "]", key})
        if (fields.contains(candidate)) return fields.value(candidate);
    return {};
}

// Nome da placa a partir do banco de ids PCI (ex.: 8086:46A8 -> Intel Alder Lake-P GT2 [Iris Xe Graphics]).
QString pciName(const QString &pciId) {
    const QStringList ids = pciId.toLower().split(':');
    if (ids.size() != 2) return {};
    for (const QString &path : {QStringLiteral("/usr/share/hwdata/pci.ids"), QStringLiteral("/usr/share/misc/pci.ids")}) {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly)) continue;
        QString vendor, device;
        bool inVendor = false;
        while (!file.atEnd()) {
            const QByteArray raw = file.readLine();
            if (raw.startsWith('#') || raw.trimmed().isEmpty()) continue;
            const QString line = QString::fromUtf8(raw).trimmed();
            if (!raw.startsWith('\t')) {                       // fornecedor
                inVendor = line.startsWith(ids[0] + "  ");
                if (inVendor) vendor = line.mid(6).trimmed();
                else if (!vendor.isEmpty()) break;             // passou do fornecedor
            } else if (inVendor && !raw.startsWith("\t\t") && line.startsWith(ids[1] + "  ")) {
                device = line.mid(6).trimmed();
                break;
            }
        }
        if (vendor.isEmpty()) continue;
        vendor.remove(QRegularExpression(" (Corporation|Corp\\.|Inc\\.|Technologies|\\[AMD/ATI\\]|\\(.*\\))$")).remove("Advanced Micro Devices, Inc. ");
        if (vendor.startsWith("Advanced Micro Devices")) vendor = "AMD";
        if (vendor.startsWith("NVIDIA")) vendor = "NVIDIA";
        if (vendor.startsWith("Intel")) vendor = "Intel";
        QString name = device;
        const int open = name.indexOf('['), close = name.lastIndexOf(']');
        if (open >= 0 && close > open) name = name.mid(open + 1, close - open - 1);
        return name.isEmpty() ? vendor : (name.startsWith(vendor) ? name : vendor + " " + name);
    }
    return {};
}
}

SystemClient::SystemClient(QObject *parent) : QObject(parent) {
    findBacklight();

    // Nenhum temporizador liga sozinho: veja acquire()/apply().
    m_audioTimer.setInterval(60000);          // só uma rede de segurança: o áudio é atualizado por eventos
    connect(&m_audioTimer, &QTimer::timeout, this, &SystemClient::pollAudio);
    m_audioDebounce.setSingleShot(true); m_audioDebounce.setInterval(150);
    connect(&m_audioDebounce, &QTimer::timeout, this, &SystemClient::pollAudio);
    m_brightnessTimer.setInterval(3000);
    connect(&m_brightnessTimer, &QTimer::timeout, this, &SystemClient::pollBrightness);
    m_btTimer.setInterval(5000);
    connect(&m_btTimer, &QTimer::timeout, this, &SystemClient::pollBluetooth);
    m_gpuTimer.setInterval(2000);
    connect(&m_gpuTimer, &QTimer::timeout, this, &SystemClient::sampleGpu);
    m_topTimer.setInterval(3000);
    connect(&m_topTimer, &QTimer::timeout, this, &SystemClient::sampleProcesses);
    m_quickTimer.setInterval(4000);
    connect(&m_quickTimer, &QTimer::timeout, this, &SystemClient::pollQuick);

    // Mudanças de volume/brilho são aplicadas em lote enquanto o controle é arrastado.
    m_applyAudio.setSingleShot(true); m_applyAudio.setInterval(70);
    connect(&m_applyAudio, &QTimer::timeout, this, [this] {
        if (m_pendingVolume < 0) return;
        const int percent = qRound(m_pendingVolume * 100);
        m_pendingVolume = -1;
        run({"set-sink-volume", "@DEFAULT_SINK@", QString::number(percent) + "%"}, [this](const QByteArray &) { QTimer::singleShot(300, this, &SystemClient::pollAudio); });
    });
    m_applyBrightness.setSingleShot(true); m_applyBrightness.setInterval(80);
    connect(&m_applyBrightness, &QTimer::timeout, this, [this] {
        if (m_pendingBrightness < 0 || m_backlight.isEmpty()) return;
        auto message = QDBusMessage::createMethodCall("org.freedesktop.login1", "/org/freedesktop/login1/session/auto",
                                                      "org.freedesktop.login1.Session", "SetBrightness");
        message << QStringLiteral("backlight") << m_backlight << uint(m_pendingBrightness);
        QDBusConnection::systemBus().asyncCall(message, 3000);
        m_pendingBrightness = -1;
    });
}

SystemClient::~SystemClient() {
    // Remover o widget não pode deixar a luz noturna pausada ou a tela sem apagar até reiniciar o Plasma.
    setDoNotDisturb(false); setNightLight(true); setCaffeine(false);
    if (!m_audioEvents) return;
    m_audioEvents->disconnect(this);
    m_audioEvents->kill();
    m_audioEvents->waitForFinished(500);
}

// ── Quem precisa de quê ───────────────────────────────────────────────────
void SystemClient::acquire(const QString &topic) {
    if (++m_users[topic] == 1) apply(topic);
}

void SystemClient::release(const QString &topic) {
    auto it = m_users.find(topic);
    if (it == m_users.end() || it.value() == 0) return;
    if (--it.value() == 0) apply(topic);
}

void SystemClient::setActive(bool on) {
    if (on == m_active) return;
    m_active = on;
    for (auto it = m_users.cbegin(); it != m_users.cend(); ++it) apply(it.key());
    emit activeChanged();
}

// Liga ou desliga as leituras de um assunto conforme haja interessados e o widget esteja ativo.
void SystemClient::apply(const QString &topic) {
    // As ações rápidas também aparecem na barra lateral, que fica sempre à vista mesmo com o widget recolhido.
    const bool want = (m_active || topic == "quick") && m_users.value(topic) > 0;
    if (topic == "audio") {
        if (want && !m_audioTimer.isActive()) { pollAudio(); m_audioTimer.start(); startAudioEvents(); }
        else if (!want) { m_audioTimer.stop(); m_audioDebounce.stop(); stopAudioEvents(); }
    } else if (topic == "brightness") {
        if (want && !m_brightnessTimer.isActive()) { pollBrightness(); m_brightnessTimer.start(); }
        else if (!want) m_brightnessTimer.stop();
    } else if (topic == "bluetooth") {
        if (want && !m_btTimer.isActive()) { pollBluetooth(); m_btTimer.start(); }
        else if (!want) m_btTimer.stop();
    } else if (topic == "gpu") {
        if (want && !m_gpuTimer.isActive()) {
            if (!m_gpuLoaded) { m_gpuLoaded = true; findGpu(); }
            m_prevRc6 = -1;   // a estimativa de uso precisa de duas leituras seguidas
            sampleGpu(); m_gpuTimer.start();
        } else if (!want) m_gpuTimer.stop();
    } else if (topic == "quick") {
        if (want && !m_quickTimer.isActive()) { pollQuick(); m_quickTimer.start(); }
        else if (!want) m_quickTimer.stop();
    } else if (topic == "top") {
        if (want && !m_topActive) {
            m_topActive = true; m_prevJiffies.clear(); m_prevTopAt = 0;
            sampleProcesses(); m_topTimer.start();
            emit topChanged();
        } else if (!want && m_topActive) {
            m_topActive = false; m_topTimer.stop();
            emit topChanged();
        }
    }
}

// O áudio é atualizado quando o sistema avisa (pactl subscribe), não por consulta periódica.
void SystemClient::startAudioEvents() {
    if (m_audioEvents) return;
    auto *process = new QProcess(this);
    m_audioEvents = process;
    connect(process, &QProcess::readyReadStandardOutput, this, [this, process] {
        for (const QByteArray &line : process->readAllStandardOutput().split('\n')) {
            // "Event 'change' on sink #53", "Event 'change' on server": volume, mudo e saída padrão
            if (line.contains(" on sink #") || line.contains(" on server")) m_audioDebounce.start();
        }
    });
    connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this, [this, process](int, QProcess::ExitStatus) {
        process->deleteLater();
        if (m_audioEvents == process) m_audioEvents = nullptr;
        if (m_active && m_users.value("audio") > 0) QTimer::singleShot(3000, this, &SystemClient::startAudioEvents);
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) { process->deleteLater(); if (m_audioEvents == process) m_audioEvents = nullptr; }
    });
    process->start("pactl", {"subscribe"});
}

void SystemClient::stopAudioEvents() {
    if (!m_audioEvents) return;
    QProcess *process = m_audioEvents;
    m_audioEvents = nullptr;
    process->disconnect(this);
    process->terminate();
    connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), process, &QObject::deleteLater);
    QTimer::singleShot(1500, process, [process] { if (process->state() != QProcess::NotRunning) process->kill(); });
}

// ── Execução de pactl ─────────────────────────────────────────────────────
void SystemClient::run(const QStringList &args, std::function<void(const QByteArray &)> done) {
    auto *process = new QProcess(this);
    connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this, [process, done](int, QProcess::ExitStatus) {
        const QByteArray out = process->readAllStandardOutput();
        process->deleteLater();
        if (done) done(out);
    });
    connect(process, &QProcess::errorOccurred, this, [process, done](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart) return;
        process->deleteLater();
        if (done) done({});
    });
    process->start("pactl", args);
}

// ── Áudio ─────────────────────────────────────────────────────────────────
void SystemClient::pollAudio() {
    if (m_audioBusy) { m_audioDirty = true; return; }
    m_audioBusy = true;
    run({"-f", "json", "info"}, [this](const QByteArray &info) {
        const QString defaultSink = QJsonDocument::fromJson(info).object().value("default_sink_name").toString();
        run({"-f", "json", "list", "sinks"}, [this, defaultSink](const QByteArray &out) {
            m_audioBusy = false;
            if (m_audioDirty) { m_audioDirty = false; QTimer::singleShot(0, this, &SystemClient::pollAudio); }
            const QJsonArray sinks = QJsonDocument::fromJson(out).array();
            QVariantList list;
            bool found = false;
            for (const auto &value : sinks) {
                const QJsonObject sink = value.toObject();
                const QString id = sink.value("name").toString();
                QString name = sink.value("description").toString();
                if (name.isEmpty()) name = id;
                list.append(QVariantMap{{"id", id}, {"name", name}});
                if (id != defaultSink) continue;
                found = true;
                m_audioMuted = sink.value("mute").toBool();
                const QJsonObject volumes = sink.value("volume").toObject();
                if (!volumes.isEmpty() && m_pendingVolume < 0)
                    m_audioVolume = volumes.begin().value().toObject().value("value").toDouble() / 65536.0;
            }
            const bool available = !sinks.isEmpty() && found;
            if (available != m_audioAvailable || list != m_audioSinks || defaultSink != m_audioSink || available) {
                m_audioAvailable = available; m_audioSinks = list; m_audioSink = defaultSink;
                emit audioChanged();
            }
        });
    });
}

void SystemClient::setAudioVolume(double volume) {
    m_audioVolume = qBound(0.0, volume, 1.5);
    m_pendingVolume = m_audioVolume;
    if (m_audioVolume > 0 && m_audioMuted) setAudioMuted(false);
    emit audioChanged();
    m_applyAudio.start();
}

void SystemClient::setAudioMuted(bool muted) {
    m_audioMuted = muted;
    emit audioChanged();
    run({"set-sink-mute", "@DEFAULT_SINK@", muted ? "1" : "0"}, [this](const QByteArray &) { QTimer::singleShot(300, this, &SystemClient::pollAudio); });
}

void SystemClient::setAudioSink(const QString &id) {
    if (id.isEmpty() || id == m_audioSink) return;
    m_audioSink = id;
    emit audioChanged();
    run({"set-default-sink", id}, [this, id](const QByteArray &) {
        // Programas que já estavam tocando vão junto para a nova saída.
        run({"list", "short", "sink-inputs"}, [this, id](const QByteArray &out) {
            for (const QByteArray &line : out.split('\n')) {
                const QByteArray number = line.split('\t').value(0).trimmed();
                if (!number.isEmpty()) run({"move-sink-input", QString::fromLatin1(number), id});
            }
            QTimer::singleShot(400, this, &SystemClient::pollAudio);
        });
    });
}

// ── Brilho ────────────────────────────────────────────────────────────────
void SystemClient::findBacklight() {
    const QDir dir("/sys/class/backlight");
    QStringList names = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    // Prefere o painel interno de fabricantes conhecidos.
    std::sort(names.begin(), names.end(), [](const QString &a, const QString &b) {
        auto rank = [](const QString &n) { return n.startsWith("intel") || n.startsWith("amdgpu") || n.startsWith("nvidia") ? 0 : 1; };
        return rank(a) < rank(b);
    });
    for (const QString &name : names)
        if (readNumber(dir.filePath(name + "/max_brightness"), 0) > 0) { m_backlight = name; return; }
}

void SystemClient::pollBrightness() {
    if (m_backlight.isEmpty() || m_pendingBrightness >= 0) return;
    const QString base = "/sys/class/backlight/" + m_backlight;
    const int max = int(readNumber(base + "/max_brightness", 0)), value = int(readNumber(base + "/brightness", 0));
    if (max != m_brightnessMax || value != m_brightnessValue) { m_brightnessMax = max; m_brightnessValue = value; emit brightnessChanged(); }
    else if (!m_brightnessMax) { m_brightnessMax = max; emit brightnessChanged(); }
}

void SystemClient::setBrightness(double fraction) {
    if (m_backlight.isEmpty() || m_brightnessMax <= 0) return;
    // Nunca deixa a tela totalmente apagada.
    m_brightnessValue = qBound(qMax(1, m_brightnessMax / 20), int(qRound(fraction * m_brightnessMax)), m_brightnessMax);
    m_pendingBrightness = m_brightnessValue;
    emit brightnessChanged();
    m_applyBrightness.start();
    QTimer::singleShot(600, this, [this] { m_pendingBrightness = -1; });
}

// ── Bluetooth ─────────────────────────────────────────────────────────────
namespace {
bool bluetoothSoftBlocked() {
    const QDir dir("/sys/class/rfkill");
    for (const QString &name : dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot))
        if (readText(dir.filePath(name + "/type")) == "bluetooth") return readText(dir.filePath(name + "/soft")) == "1";
    return false;
}
}

void SystemClient::pollBluetooth() {
    auto bus = QDBusConnection::systemBus();
    if (!bus.isConnected() || m_btBusy) return;
    m_btBusy = true;
    auto message = QDBusMessage::createMethodCall("org.bluez", "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects");
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(message, 3000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        m_btBusy = false;
        const QDBusMessage reply = w->reply();
        const bool blocked = bluetoothSoftBlocked();
        bool available = false, powered = false;
        QString adapter;
        QVariantList devices;
        if (reply.type() == QDBusMessage::ReplyMessage && !reply.arguments().isEmpty()) {
            QMap<QString, QVariantMap> found;   // caminho -> propriedades combinadas das interfaces
            const QDBusArgument arg = reply.arguments().first().value<QDBusArgument>();
            arg.beginMap();
            while (!arg.atEnd()) {
                arg.beginMapEntry();
                QDBusObjectPath path;
                arg >> path;
                arg.beginMap();
                while (!arg.atEnd()) {
                    arg.beginMapEntry();
                    QString iface;
                    QVariantMap props;
                    arg >> iface >> props;
                    arg.endMapEntry();
                    if (iface == "org.bluez.Adapter1") {
                        if (!available) { available = true; adapter = path.path(); powered = props.value("Powered").toBool(); }
                    } else if (iface == "org.bluez.Device1" || iface == "org.bluez.Battery1") {
                        QVariantMap &entry = found[path.path()];
                        for (auto it = props.begin(); it != props.end(); ++it) entry.insert(iface.section('.', -1) + "." + it.key(), it.value());
                    }
                }
                arg.endMap();
                arg.endMapEntry();
            }
            arg.endMap();
            for (auto it = found.begin(); it != found.end(); ++it) {
                const QVariantMap &p = it.value();
                if (!p.contains("Device1.Address")) continue;
                const bool connected = p.value("Device1.Connected").toBool();
                if (!connected && !p.value("Device1.Paired").toBool()) continue;   // ignora o que só foi visto na busca
                QString name = p.value("Device1.Alias").toString();
                if (name.isEmpty()) name = p.value("Device1.Name").toString();
                if (name.isEmpty()) name = p.value("Device1.Address").toString();
                devices.append(QVariantMap{{"path", it.key()}, {"name", name}, {"icon", p.value("Device1.Icon").toString()},
                                           {"connected", connected},
                                           {"battery", p.contains("Battery1.Percentage") ? p.value("Battery1.Percentage").toInt() : -1}});
            }
            std::sort(devices.begin(), devices.end(), [](const QVariant &a, const QVariant &b) {
                const auto x = a.toMap(), y = b.toMap();
                if (x.value("connected").toBool() != y.value("connected").toBool()) return x.value("connected").toBool();
                return x.value("name").toString().toLower() < y.value("name").toString().toLower();
            });
        }
        if (available != m_btAvailable || powered != m_btPowered || blocked != m_btBlocked || devices != m_btDevices || adapter != m_btAdapter) {
            m_btAvailable = available; m_btPowered = powered; m_btBlocked = blocked; m_btDevices = devices; m_btAdapter = adapter;
            emit bluetoothChanged();
        }
    });
}

void SystemClient::setBluetoothPowered(bool on) {
    auto setPowered = [this, on] {
        if (m_btAdapter.isEmpty()) return;
        auto message = QDBusMessage::createMethodCall("org.bluez", m_btAdapter, "org.freedesktop.DBus.Properties", "Set");
        message << QStringLiteral("org.bluez.Adapter1") << QStringLiteral("Powered") << QVariant::fromValue(QDBusVariant(on));
        QDBusConnection::systemBus().asyncCall(message, 3000);
        QTimer::singleShot(800, this, &SystemClient::pollBluetooth);
        QTimer::singleShot(2500, this, &SystemClient::pollBluetooth);
    };
    if (on && m_btBlocked) {   // bloqueado por software (tecla Fn/rfkill): libera primeiro
        auto *process = new QProcess(this);
        connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this, [process, setPowered](int, QProcess::ExitStatus) {
            process->deleteLater();
            QTimer::singleShot(600, process->parent(), setPowered);
        });
        connect(process, &QProcess::errorOccurred, this, [process](QProcess::ProcessError) { process->deleteLater(); });
        process->start("rfkill", {"unblock", "bluetooth"});
        return;
    }
    setPowered();
}

void SystemClient::toggleBluetoothDevice(const QString &path) {
    bool connected = false, known = false;
    for (const auto &v : m_btDevices) {
        const auto d = v.toMap();
        if (d.value("path").toString() == path) { connected = d.value("connected").toBool(); known = true; }
    }
    if (!known) return;
    auto message = QDBusMessage::createMethodCall("org.bluez", path, "org.bluez.Device1", connected ? "Disconnect" : "Connect");
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message, 25000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) { w->deleteLater(); pollBluetooth(); });
}

// ── Processos ─────────────────────────────────────────────────────────────
void SystemClient::acquireTop() { acquire("top"); }
void SystemClient::releaseTop() { release("top"); }

void SystemClient::sampleProcesses() {
    const double ticks = double(sysconf(_SC_CLK_TCK)), page = double(sysconf(_SC_PAGESIZE));
    const int cores = qMax(1, QThread::idealThreadCount());
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const double seconds = m_prevTopAt > 0 ? (now - m_prevTopAt) / 1000.0 : 0;

    struct Group { double cpu = 0, memory = 0; int count = 0; };
    QHash<QString, Group> groups;
    QHash<qint64, qint64> current;
    const QDir proc("/proc");
    for (const QString &entry : proc.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        bool ok = false;
        const qint64 pid = entry.toLongLong(&ok);
        if (!ok || pid <= 2) continue;
        QFile file(proc.filePath(entry + "/stat"));
        if (!file.open(QIODevice::ReadOnly)) continue;
        const QString stat = QString::fromUtf8(file.readAll());
        const int open = stat.indexOf('('), close = stat.lastIndexOf(')');
        if (open < 0 || close < open) continue;
        const QStringList f = stat.mid(close + 2).split(' ');
        if (f.size() < 22 || f.value(1).toLongLong() == 2) continue;   // thread do kernel
        const double rss = f.value(21).toDouble() * page;
        if (rss <= 0) continue;
        const qint64 jiffies = f.value(11).toLongLong() + f.value(12).toLongLong();
        current.insert(pid, jiffies);
        const QString name = friendlyName(stat.mid(open + 1, close - open - 1));
        Group &g = groups[name];
        g.memory += rss; g.count++;
        if (seconds > 0 && m_prevJiffies.contains(pid))
            g.cpu += qMax<qint64>(0, jiffies - m_prevJiffies.value(pid)) / (ticks * seconds) * 100.0 / cores;
    }
    m_prevJiffies = current;
    m_prevTopAt = now;

    QList<QPair<QString, Group>> all;
    for (auto it = groups.begin(); it != groups.end(); ++it) all.append({it.key(), it.value()});
    auto toList = [&](auto less) {
        std::sort(all.begin(), all.end(), less);
        QVariantList out;
        for (int i = 0; i < all.size() && out.size() < 5; ++i)
            out.append(QVariantMap{{"name", all[i].first}, {"cpu", all[i].second.cpu}, {"memory", all[i].second.memory}, {"count", all[i].second.count}});
        return out;
    };
    m_topCpu = seconds > 0 ? toList([](const auto &a, const auto &b) { return a.second.cpu > b.second.cpu; }) : QVariantList();
    m_topMemory = toList([](const auto &a, const auto &b) { return a.second.memory > b.second.memory; });
    emit topChanged();
}

// ── GPU ───────────────────────────────────────────────────────────────────
void SystemClient::findGpu() {
    const QDir drm("/sys/class/drm");
    int best = -1;
    for (const QString &name : drm.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        static const QRegularExpression card("^card\\d+$");
        if (!card.match(name).hasMatch()) continue;
        const QString driver = QFileInfo(drm.filePath(name + "/device/driver")).canonicalFilePath().section('/', -1);
        if (driver.isEmpty()) continue;
        // Prefere placa dedicada (amdgpu/nvidia) à integrada.
        const int rank = driver == "amdgpu" || driver == "nvidia" ? 2 : driver == "i915" || driver == "xe" ? 1 : 0;
        if (rank > best) { best = rank; m_gpuDir = drm.filePath(name); m_gpuDriver = driver; }
    }
    if (m_gpuDir.isEmpty()) return;
    QString pciId;
    for (const QString &line : readText(m_gpuDir + "/device/uevent").split('\n'))
        if (line.startsWith("PCI_ID=")) pciId = line.mid(7);
    m_gpuName = pciName(pciId);
    if (m_gpuName.isEmpty()) m_gpuName = m_gpuDriver == "i915" || m_gpuDriver == "xe" ? "Intel Graphics" : m_gpuDriver == "amdgpu" ? "AMD Radeon" : m_gpuDriver;
}

void SystemClient::sampleGpu() {
    if (m_gpuDir.isEmpty()) return;
    const QString dev = m_gpuDir + "/device";
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    double usage = -1, freq = -1, freqMax = -1, temp = -1, memUsed = -1, memTotal = -1;

    if (m_gpuDriver == "amdgpu") {
        usage = readNumber(dev + "/gpu_busy_percent");
        memUsed = readNumber(dev + "/mem_info_vram_used");
        memTotal = readNumber(dev + "/mem_info_vram_total");
        const QStringList lines = readText(dev + "/pp_dpm_sclk").split('\n', Qt::SkipEmptyParts);
        static const QRegularExpression mhz("(\\d+)\\s*Mhz", QRegularExpression::CaseInsensitiveOption);
        for (const QString &line : lines) {
            const auto m = mhz.match(line);
            if (!m.hasMatch()) continue;
            const double value = m.captured(1).toDouble();
            if (line.contains('*')) freq = value;
            freqMax = qMax(freqMax, value);
        }
        const QDir hw(dev + "/hwmon");
        for (const QString &h : hw.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
            const double t = readNumber(hw.filePath(h + "/temp1_input"));
            if (t > 0) { temp = t / 1000.0; break; }
        }
    } else if (m_gpuDriver == "i915" || m_gpuDriver == "xe") {
        // Uso estimado pelo tempo fora do estado de repouso (RC6): quanto menos repouso, mais trabalho.
        QString rc6 = m_gpuDir + "/gt/gt0/rc6_residency_ms";
        if (!QFileInfo::exists(rc6)) rc6 = dev + "/tile0/gt0/gtidle/idle_residency_ms";
        const double residency = readNumber(rc6);
        if (residency >= 0) {
            if (m_prevRc6 >= 0 && now > m_prevRc6At) {
                const double idle = (residency - m_prevRc6) / double(now - m_prevRc6At);
                usage = qBound(0.0, (1.0 - idle) * 100.0, 100.0);
            }
            m_prevRc6 = qint64(residency); m_prevRc6At = now;
        }
        freq = readNumber(m_gpuDir + "/gt_act_freq_mhz");
        if (freq < 0) freq = readNumber(m_gpuDir + "/gt/gt0/rps_act_freq_mhz");
        if (freq < 0) freq = readNumber(dev + "/tile0/gt0/freq0/act_freq");
        freqMax = readNumber(m_gpuDir + "/gt_max_freq_mhz");
        if (freqMax < 0) freqMax = readNumber(m_gpuDir + "/gt/gt0/rps_max_freq_mhz");
        if (freqMax < 0) freqMax = readNumber(dev + "/tile0/gt0/freq0/max_freq");
    }

    if (usage >= 0) {
        m_gpuHistory.append(usage);
        while (m_gpuHistory.size() > 60) m_gpuHistory.removeFirst();
    }
    m_gpuUsage = usage; m_gpuFreq = freq; m_gpuFreqMax = freqMax; m_gpuTemp = temp; m_gpuMemUsed = memUsed; m_gpuMemTotal = memTotal;
    emit gpuChanged();
}

// ── Atalhos ───────────────────────────────────────────────────────────────
QVariantList SystemClient::applications() {
    if (!m_apps.isEmpty()) return m_apps;
    QStringList dirs;
    for (const QString &d : QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation)) dirs << d;
    dirs << QDir::homePath() + "/.local/share/flatpak/exports/share/applications" << "/var/lib/flatpak/exports/share/applications";
    QHash<QString, DesktopEntry> byId;
    for (const QString &dirPath : dirs) {   // as pastas do usuário vêm primeiro e vencem
        const QDir dir(dirPath);
        for (const QString &file : dir.entryList({"*.desktop"}, QDir::Files)) {
            const QString id = file.chopped(8);
            if (byId.contains(id)) continue;
            QFile f(dir.filePath(file));
            if (!f.open(QIODevice::ReadOnly)) continue;
            QMap<QString, QString> fields;
            bool inEntry = false;
            for (const QByteArray &raw : f.readAll().split('\n')) {
                const QString line = QString::fromUtf8(raw).trimmed();
                if (line.startsWith('[')) { inEntry = line == "[Desktop Entry]"; continue; }
                if (!inEntry || line.isEmpty() || line.startsWith('#')) continue;
                const int eq = line.indexOf('=');
                if (eq > 0) fields.insert(line.left(eq).trimmed(), line.mid(eq + 1).trimmed());
            }
            if (fields.value("Type") != "Application" || fields.value("NoDisplay") == "true" || fields.value("Hidden") == "true") continue;
            const QString name = localized(fields, "Name");
            if (name.isEmpty()) continue;
            byId.insert(id, {id, name, fields.value("Icon")});
        }
    }
    QList<DesktopEntry> entries = byId.values();
    std::sort(entries.begin(), entries.end(), [](const DesktopEntry &a, const DesktopEntry &b) { return a.name.toLower() < b.name.toLower(); });
    for (const auto &e : entries) m_apps.append(QVariantMap{{"id", e.id}, {"name", e.name}, {"icon", e.icon}});
    return m_apps;
}

bool SystemClient::launch(const QString &target) {
    const QString value = target.trimmed();
    if (value.startsWith("app:")) {
        static const QRegularExpression valid("^[A-Za-z0-9._+-]+$");
        const QString id = value.mid(4);
        return valid.match(id).hasMatch() && QProcess::startDetached("gtk-launch", {id});
    }
    // Só endereços e caminhos: nada é executado como comando de terminal.
    const QUrl url(value);
    if (url.scheme() == "http" || url.scheme() == "https" || url.scheme() == "mailto")
        return QProcess::startDetached("xdg-open", {url.toString()});
    QString path = value;
    if (path.startsWith("~/")) path = QDir::homePath() + path.mid(1);
    if (path.startsWith("file://")) path = QUrl(path).toLocalFile();
    return QFileInfo::exists(path) && QProcess::startDetached("xdg-open", {path});
}

// ── Ações rápidas ─────────────────────────────────────────────────────────
namespace {
// Lê todas as propriedades de uma interface sem travar a interface; done recebe {} se o serviço não existir.
void getAll(QObject *owner, const QDBusConnection &bus, const QString &service, const QString &path, const QString &iface,
            std::function<void(const QVariantMap &, bool)> done) {
    auto message = QDBusMessage::createMethodCall(service, path, "org.freedesktop.DBus.Properties", "GetAll");
    message << iface;
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(message, 3000), owner);
    QObject::connect(watcher, &QDBusPendingCallWatcher::finished, owner, [done](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        const QDBusMessage reply = w->reply();
        if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) { done({}, false); return; }
        done(qdbus_cast<QVariantMap>(reply.arguments().first()), true);
    });
}

void setDBusProperty(const QDBusConnection &bus, const QString &service, const QString &path, const QString &iface,
                 const QString &name, const QVariant &value) {
    auto message = QDBusMessage::createMethodCall(service, path, "org.freedesktop.DBus.Properties", "Set");
    message << iface << name << QVariant::fromValue(QDBusVariant(value));
    bus.asyncCall(message, 5000);
}

// Chama um método que devolve um "cookie" (uint) e o entrega a done (0 se falhar).
void callCookie(QObject *owner, const QDBusConnection &bus, QDBusMessage message, std::function<void(uint)> done) {
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(message, 3000), owner);
    QObject::connect(watcher, &QDBusPendingCallWatcher::finished, owner, [done](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        const QDBusMessage reply = w->reply();
        done(reply.type() == QDBusMessage::ReplyMessage && !reply.arguments().isEmpty() ? reply.arguments().first().toUInt() : 0);
    });
}

bool hasWifiHardware() { return !QDir("/sys/class/ieee80211").entryList(QDir::Dirs | QDir::NoDotAndDotDot).isEmpty(); }
bool canSuspendToRam() { return readText("/sys/power/state").split(' ').contains("mem"); }
}

void SystemClient::setQuick(const QVariantMap &values) {
    bool changed = false;
    for (auto it = values.begin(); it != values.end(); ++it)
        if (m_quick.value(it.key()) != it.value()) { m_quick.insert(it.key(), it.value()); changed = true; }
    if (changed) emit quickChanged();
}

void SystemClient::pollQuick() {
    auto session = QDBusConnection::sessionBus(), system = QDBusConnection::systemBus();
    setQuick({{"wifiAvailable", hasWifiHardware()}, {"canSuspend", canSuspendToRam()},
              {"dnd", m_dndCookie != 0}, {"caffeine", m_screenCookie != 0 || m_sleepCookie != 0}});

    getAll(this, session, "org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications",
           [this](const QVariantMap &p, bool ok) {
        const bool inhibited = p.value("Inhibited").toBool();
        setQuick({{"dndAvailable", ok}, {"dndOther", inhibited && m_dndCookie == 0}});
    });
    getAll(this, session, "org.kde.KWin", "/org/kde/KWin/NightLight", "org.kde.KWin.NightLight", [this](const QVariantMap &p, bool ok) {
        const bool enabled = p.value("enabled").toBool(), inhibited = p.value("inhibited").toBool();
        setQuick({{"nightAvailable", ok && p.value("available").toBool()}, {"nightEnabled", enabled},
                  {"night", enabled && !inhibited}, {"nightOther", inhibited && m_nightCookie == 0}});
    });

    // power-profiles-daemon mudou de nome; tenta o atual e depois o antigo.
    auto readProfiles = [this, system](const QString &service, const QString &path, const QString &iface, auto &&fallback) {
        getAll(this, system, service, path, iface, [this, service, fallback](const QVariantMap &p, bool ok) {
            if (!ok) { fallback(); return; }
            m_profilesService = service;
            QVariantList profiles;
            const QDBusArgument arg = p.value("Profiles").value<QDBusArgument>();
            if (arg.currentType() == QDBusArgument::ArrayType) {
                arg.beginArray();
                while (!arg.atEnd()) { QVariantMap entry; arg >> entry; profiles.append(entry.value("Profile").toString()); }
                arg.endArray();
            }
            setQuick({{"profiles", profiles}, {"profile", p.value("ActiveProfile").toString()}});
        });
    };
    readProfiles(QStringLiteral("org.freedesktop.UPower.PowerProfiles"), QStringLiteral("/org/freedesktop/UPower/PowerProfiles"),
                 QStringLiteral("org.freedesktop.UPower.PowerProfiles"), [this, readProfiles] {
        readProfiles(QStringLiteral("net.hadess.PowerProfiles"), QStringLiteral("/net/hadess/PowerProfiles"),
                     QStringLiteral("net.hadess.PowerProfiles"), [this] { m_profilesService.clear(); setQuick({{"profiles", QVariantList{}}, {"profile", QString()}}); });
    });

    getAll(this, system, "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager", "org.freedesktop.NetworkManager",
           [this](const QVariantMap &p, bool ok) {
        setQuick({{"wifi", ok && p.value("WirelessEnabled").toBool()},
                  {"wifiAvailable", ok && hasWifiHardware() && p.value("WirelessHardwareEnabled").toBool()}});
    });
}

void SystemClient::setDoNotDisturb(bool on) {
    auto bus = QDBusConnection::sessionBus();
    if (!on) {
        if (m_dndCookie == 0) return;
        auto message = QDBusMessage::createMethodCall("org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "UnInhibit");
        message << m_dndCookie;
        bus.asyncCall(message, 3000);
        m_dndCookie = 0;
        setQuick({{"dnd", false}});
        QTimer::singleShot(400, this, &SystemClient::pollQuick);
        return;
    }
    if (m_dndCookie != 0) return;
    auto message = QDBusMessage::createMethodCall("org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "Inhibit");
    message << QStringLiteral("plasdria") << QStringLiteral("Não perturbe ligado no Plasdria") << QVariantMap{};
    callCookie(this, bus, message, [this](uint cookie) { m_dndCookie = cookie; setQuick({{"dnd", cookie != 0}}); pollQuick(); });
}

void SystemClient::setNightLight(bool on) {
    auto bus = QDBusConnection::sessionBus();
    if (on) {   // volta a valer o que está nas Configurações do sistema
        if (m_nightCookie == 0) return;
        auto message = QDBusMessage::createMethodCall("org.kde.KWin", "/org/kde/KWin/NightLight", "org.kde.KWin.NightLight", "uninhibit");
        message << m_nightCookie;
        bus.asyncCall(message, 3000);
        m_nightCookie = 0;
        QTimer::singleShot(400, this, &SystemClient::pollQuick);
        return;
    }
    if (m_nightCookie != 0) return;
    auto message = QDBusMessage::createMethodCall("org.kde.KWin", "/org/kde/KWin/NightLight", "org.kde.KWin.NightLight", "inhibit");
    callCookie(this, bus, message, [this](uint cookie) { m_nightCookie = cookie; pollQuick(); });
}

void SystemClient::setPowerProfile(const QString &profile) {
    if (m_profilesService.isEmpty() || !m_quick.value("profiles").toList().contains(profile)) return;
    const bool modern = m_profilesService.startsWith("org.freedesktop");
    setDBusProperty(QDBusConnection::systemBus(), m_profilesService,
                modern ? "/org/freedesktop/UPower/PowerProfiles" : "/net/hadess/PowerProfiles",
                m_profilesService, "ActiveProfile", profile);
    setQuick({{"profile", profile}});
    QTimer::singleShot(600, this, &SystemClient::pollQuick);
}

// Mantém acordado: nem bloqueio/apagar da tela, nem suspensão automática.
void SystemClient::setCaffeine(bool on) {
    auto bus = QDBusConnection::sessionBus();
    if (!on) {
        if (m_screenCookie) {
            auto m = QDBusMessage::createMethodCall("org.freedesktop.ScreenSaver", "/ScreenSaver", "org.freedesktop.ScreenSaver", "UnInhibit");
            m << m_screenCookie; bus.asyncCall(m, 3000); m_screenCookie = 0;
        }
        if (m_sleepCookie) {
            auto m = QDBusMessage::createMethodCall("org.freedesktop.PowerManagement", "/org/freedesktop/PowerManagement/Inhibit", "org.freedesktop.PowerManagement.Inhibit", "UnInhibit");
            m << m_sleepCookie; bus.asyncCall(m, 3000); m_sleepCookie = 0;
        }
        setQuick({{"caffeine", false}});
        return;
    }
    if (m_screenCookie || m_sleepCookie) return;
    const QString app = QStringLiteral("Plasdria"), reason = QStringLiteral("Manter acordado (ação rápida)");
    auto screen = QDBusMessage::createMethodCall("org.freedesktop.ScreenSaver", "/ScreenSaver", "org.freedesktop.ScreenSaver", "Inhibit");
    screen << app << reason;
    callCookie(this, bus, screen, [this](uint cookie) { m_screenCookie = cookie; setQuick({{"caffeine", m_screenCookie || m_sleepCookie}}); });
    auto sleep = QDBusMessage::createMethodCall("org.freedesktop.PowerManagement", "/org/freedesktop/PowerManagement/Inhibit", "org.freedesktop.PowerManagement.Inhibit", "Inhibit");
    sleep << app << reason;
    callCookie(this, bus, sleep, [this](uint cookie) { m_sleepCookie = cookie; setQuick({{"caffeine", m_screenCookie || m_sleepCookie}}); });
}

void SystemClient::setWifi(bool on) {
    setDBusProperty(QDBusConnection::systemBus(), "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager",
                "org.freedesktop.NetworkManager", "WirelessEnabled", on);
    setQuick({{"wifi", on}});
    QTimer::singleShot(800, this, &SystemClient::pollQuick);
}

void SystemClient::lockScreen() {
    QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall("org.freedesktop.ScreenSaver", "/ScreenSaver", "org.freedesktop.ScreenSaver", "Lock"), 3000);
}

void SystemClient::suspend() {
    auto message = QDBusMessage::createMethodCall("org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "Suspend");
    message << true;   // interativo: o polkit pode pedir confirmação
    QDBusConnection::systemBus().asyncCall(message, 5000);
}

// Abre o diálogo do próprio Plasma (sair, reiniciar, desligar), que já pede confirmação.
void SystemClient::sessionMenu() {
    QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall("org.kde.LogoutPrompt", "/LogoutPrompt", "org.kde.LogoutPrompt", "promptAll"), 3000);
}

// ── Barra lateral ─────────────────────────────────────────────────────────
// O script roda no próprio plasmashell pela API de scripts do Plasma. Vai por um processo à parte (qdbus6):
// o widget vive dentro do plasmashell, e uma chamada a si mesmo no meio de um clique poderia travar.
void SystemClient::runShellScript(const QString &script) {
    auto *process = new QProcess(this);
    connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this, [this, process](int code, QProcess::ExitStatus) {
        const QString out = QString::fromUtf8(process->readAllStandardOutput()).trimmed();
        process->deleteLater();
        const QString status = code == 0 && !out.isEmpty() ? out.section('\n', -1).trimmed() : QStringLiteral("error");
        if (status.startsWith("state:")) {   // só consulta, sem mensagem: "state:pinned:right"
            setSidebarState(status.section(':', 1, 1));
            const QString edge = status.section(':', 2, 2);
            const QStringList busy = status.section(':', 3, 3).split(',', Qt::SkipEmptyParts);
            if (edge != m_sidebarEdge || busy != m_sidebarBusyEdges) { m_sidebarEdge = edge; m_sidebarBusyEdges = busy; emit sidebarStateChanged(); }
            return;
        }
        if (status.startsWith("occupied:")) {
            m_sidebarBusyEdges = status.section(':', 1, 1).split(',', Qt::SkipEmptyParts);
            emit sidebarStateChanged();
            emit sidebarResult(QStringLiteral("occupied"));
            return;
        }
        if (status.startsWith("created:") || status.startsWith("moved:")) {
            m_sidebarEdge = status.section(':', 1, 1);
            setSidebarState(m_sidebarState == "autohide" && status.startsWith("moved:") ? "autohide" : "pinned");
            emit sidebarStateChanged();
            emit sidebarResult(status.section(':', 0, 0));
            return;
        }
        if (status == "pinned") setSidebarState("pinned");
        else if (status == "autohide") setSidebarState("autohide");
        else if (status == "removed" || status == "none") setSidebarState("none");
        else if (status == "exists") refreshSidebar();
        emit sidebarResult(status);
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart) return;
        process->deleteLater();
        emit sidebarResult(QStringLiteral("error"));
    });
    process->start("qdbus6", {"org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", script});
}

// Acha a barra do Plasdria: o painel com um Plasdria marcado como barra (barMode) ou, para barras criadas
// antes dessa marca, um painel lateral com o Plasdria. O Plasdria solto num painel comum não conta.
static const char *kFindBar = R"JS(
function isBar(p) {
    var ws = p.widgets("local.plasdria");
    for (var i = 0; i < ws.length; ++i) {
        ws[i].currentConfigGroup = ["Data"];
        if (String(ws[i].readConfig("barMode", false)) == "true") return true;
    }
    return ws.length > 0 && (p.location == "left" || p.location == "right");
}
function markBar(p) {
    var ws = p.widgets("local.plasdria");
    for (var i = 0; i < ws.length; ++i) { ws[i].currentConfigGroup = ["Data"]; ws[i].writeConfig("barMode", true); ws[i].reloadConfig(); }
}
function thicknessFor(edge) { return edge == "top" || edge == "bottom" ? 56 : 84; }
function compactFor(edge) { return edge == "top" || edge == "bottom" ? 40 : 56; }
function isCompact(p) { return p.height < thicknessFor(p.location) - 4; }
var found = panels().filter(isBar);
// Bordas com outro painel (ex.: a barra de tarefas): no Plasma 6 painéis na mesma borda ficam um por cima do outro.
var busy = panels().filter(function (p) { return !isBar(p); }).map(function (p) { return p.location; });
)JS";

namespace {
QString jsString(const QString &value) {
    return QString::fromUtf8(QJsonDocument(QJsonArray{value}).toJson(QJsonDocument::Compact)).mid(1).chopped(1);
}
}

void SystemClient::createSidebar(const QString &edge, const QVariantMap &config) {
    static const QStringList edges = {"left", "right", "top", "bottom"};
    const QString location = edges.contains(edge) ? edge : QStringLiteral("right");
    // Os valores entram como JSON, nunca colados como código.
    QVariantMap withMark = config;
    QVariantMap data = withMark.value("Data").toMap();
    data.insert("barMode", true);
    withMark.insert("Data", data);
    const QString json = QString::fromUtf8(QJsonDocument(QJsonObject::fromVariantMap(withMark)).toJson(QJsonDocument::Compact));
    const QString script = QString::fromUtf8(kFindBar) + QStringLiteral(R"JS(
var edge = %1;
if (busy.indexOf(edge) >= 0) {
    print("occupied:" + busy.join(","));
} else if (found.length > 0) {
    // Já existe: só muda de borda.
    var b = found[0];
    markBar(b);
    if (b.location == edge) { print("exists"); } else {
        var compact = isCompact(b);   // mudar de borda mantém a barra expandida ou recolhida
        b.location = edge; b.height = compact ? compactFor(edge) : thicknessFor(edge);
        print("moved:" + edge);
    }
} else {
    var p = new Panel("org.kde.panel");
    p.location = edge;
    p.height = thicknessFor(edge);
    p.hiding = "none";
    try { p.floating = true; } catch (e) {}
    var w = p.addWidget("local.plasdria");
    var cfg = %2;
    for (var group in cfg) {
        w.currentConfigGroup = [group];
        for (var key in cfg[group]) w.writeConfig(key, cfg[group][key]);
    }
    w.reloadConfig();
    print("created:" + edge);
}
)JS").arg(jsString(location), json);
    runShellScript(script);
}

void SystemClient::removeSidebars() {
    runShellScript(QString::fromUtf8(kFindBar) + QStringLiteral(R"JS(
for (var i = 0; i < found.length; ++i) found[i].remove();
print(found.length > 0 ? "removed" : "none");
)JS"));
}

void SystemClient::setSidebarAutoHide(bool on) {
    runShellScript(QString::fromUtf8(kFindBar) + QStringLiteral(R"JS(
for (var i = 0; i < found.length; ++i) found[i].hiding = %1 ? "autohide" : "none";
print(found.length == 0 ? "none" : %1 ? "autohide" : "pinned");
)JS").arg(on ? "true" : "false"));
}

void SystemClient::refreshSidebar() {
    runShellScript(QString::fromUtf8(kFindBar) + QStringLiteral(R"JS(
print((found.length == 0 ? "state:none:" : "state:" + (found[0].hiding == "autohide" ? "autohide" : "pinned") + ":" + found[0].location) + ":" + busy.join(","));
)JS"));
}

// Recolhida: a barra fica mais fina e mostra só o essencial. Expandida: espessura normal.
void SystemClient::setSidebarCompact(bool compact) {
    runShellScript(QString::fromUtf8(kFindBar) + QStringLiteral(R"JS(
for (var i = 0; i < found.length; ++i) found[i].height = %1 ? compactFor(found[i].location) : thicknessFor(found[i].location);
print(found.length == 0 ? "none" : %1 ? "compact" : "expanded");
)JS").arg(compact ? "true" : "false"));
}
