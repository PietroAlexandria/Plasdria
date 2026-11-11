#include "speedtestclient.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRandomGenerator>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUrl>
#include <algorithm>
#include <cmath>

namespace {
constexpr int PingCount = 9;             // a primeira (conexão e TLS) é descartada
constexpr int HistoryLimit = 20;
constexpr qint64 DownloadChunk = 25'000'000;
constexpr int UploadChunk = 4 * 1024 * 1024;
constexpr int MaxFailures = 8;

QNetworkRequest request(const QUrl &url, bool http2 = false) {
    QNetworkRequest req(url);
    req.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
    req.setAttribute(QNetworkRequest::Http2AllowedAttribute, http2);   // uma conexão por fluxo, como num teste de verdade
    req.setHeader(QNetworkRequest::UserAgentHeader, "Plasdria");
    req.setTransferTimeout(20000);
    return req;
}
}

SpeedTestClient::SpeedTestClient(QObject *parent) : QObject(parent) {
    m_tick.setInterval(150);
    connect(&m_tick, &QTimer::timeout, this, &SpeedTestClient::tick);
    loadHistory();
}

QString SpeedTestClient::phase() const {
    switch (m_phase) {
    case Phase::Ping: return "ping";
    case Phase::Download: return "download";
    case Phase::Upload: return "upload";
    default: return {};
    }
}

void SpeedTestClient::start() {
    if (m_running) return;
    ++m_generation;
    m_running = true; m_phase = Phase::Ping; m_error.clear();
    m_progress = 0; m_live = 0; m_ping = m_jitter = m_download = m_upload = -1;
    m_server.clear(); m_pingSamples.clear();
    emit changed();
    pingOnce();
}

void SpeedTestClient::cancel() {
    if (!m_running) return;
    ++m_generation;
    m_tick.stop();
    abortReplies();
    m_running = false; m_phase = Phase::Idle; m_progress = 0; m_live = 0; m_error.clear();
    m_ping = m_jitter = m_download = m_upload = -1;
    emit changed();
    emit finished(false);
}

void SpeedTestClient::clearHistory() {
    m_history.clear();
    saveHistory();
    emit changed();
}

// ── Latência ──────────────────────────────────────────────────────────────
void SpeedTestClient::pingOnce() {
    const int generation = m_generation;
    QNetworkReply *reply = m_net.get(request(QUrl(m_baseUrl + "/__down?bytes=0"), true));
    m_pingReply = reply;
    m_pingClock.start();
    connect(reply, &QNetworkReply::finished, this, [this, reply, generation] {
        reply->deleteLater();
        if (generation != m_generation || !m_running) return;
        if (reply->error() != QNetworkReply::NoError) { finish("Sem conexão com o servidor de teste."); return; }
        m_pingSamples.append(m_pingClock.nsecsElapsed() / 1e6);
        if (m_server.isEmpty()) {
            // O servidor da Cloudflare diz onde fica no cabeçalho cf-ray (ex.: 8a1b2c3d4e5f-GRU).
            const QString ray = QString::fromLatin1(reply->rawHeader("cf-ray"));
            const QString site = ray.section('-', -1).toUpper();
            const QString host = QUrl(m_baseUrl).host();
            m_server = host.contains("cloudflare") ? (site.isEmpty() ? QStringLiteral("Cloudflare") : "Cloudflare · " + site) : host;
        }
        m_progress = 0.1 * m_pingSamples.size() / PingCount;
        emit changed();
        if (m_pingSamples.size() < PingCount) { pingOnce(); return; }
        QList<double> samples = m_pingSamples.mid(1);   // sem a primeira
        double jitter = 0;
        for (int i = 1; i < samples.size(); ++i) jitter += std::abs(samples[i] - samples[i - 1]);
        m_jitter = samples.size() > 1 ? jitter / (samples.size() - 1) : 0;
        std::sort(samples.begin(), samples.end());
        m_ping = samples[samples.size() / 2];
        beginTransfer(Phase::Download);
    });
}

// ── Download e upload ─────────────────────────────────────────────────────
void SpeedTestClient::beginTransfer(Phase phase) {
    m_phase = phase;
    m_bytes = m_warmBytes = 0; m_warmAt = -1; m_window.clear(); m_live = 0;
    m_replies.clear(); m_sent.clear();
    ++m_generation;
    if (phase == Phase::Upload && m_payload.isEmpty()) {
        m_payload.resize(UploadChunk);
        auto *words = reinterpret_cast<quint32 *>(m_payload.data());
        for (int i = 0; i < UploadChunk / 4; ++i) words[i] = QRandomGenerator::global()->generate();
    }
    m_clock.start();
    m_failures = 0;
    for (int i = 0; i < m_streams; ++i) spawn(m_generation);
    m_tick.start();
    emit changed();
}

void SpeedTestClient::spawn(int generation) {
    if (generation != m_generation || !m_running) return;
    QNetworkReply *reply;
    if (m_phase == Phase::Download) {
        reply = m_net.get(request(QUrl(m_baseUrl + "/__down?bytes=" + QString::number(DownloadChunk))));
        connect(reply, &QNetworkReply::readyRead, this, [this, reply, generation] {
            const qint64 n = reply->readAll().size();
            if (generation == m_generation) m_bytes += n;
        });
    } else {
        QNetworkRequest req = request(QUrl(m_baseUrl + "/__up"));
        req.setHeader(QNetworkRequest::ContentTypeHeader, "application/octet-stream");
        reply = m_net.post(req, m_payload);
        m_sent.insert(reply, 0);
        connect(reply, &QNetworkReply::uploadProgress, this, [this, reply, generation](qint64 sent, qint64) {
            if (generation != m_generation || !m_sent.contains(reply)) return;
            // O Qt às vezes reinicia a contagem de uma requisição (nova conexão): só conta o que avançou.
            if (sent > m_sent.value(reply)) m_bytes += sent - m_sent.value(reply);
            m_sent[reply] = sent;
        });
    }
    m_replies.append(reply);
    connect(reply, &QNetworkReply::finished, this, [this, reply, generation] {
        m_sent.remove(reply);
        const bool failed = reply->error() != QNetworkReply::NoError;
        reply->deleteLater();
        if (generation != m_generation || !m_running) return;
        if (failed && ++m_failures >= MaxFailures) { finish(m_phase == Phase::Download ? "O download foi interrompido." : "O upload foi interrompido."); return; }
        spawn(generation);   // cada fluxo continua pedindo mais dados até o tempo da fase acabar
    });
}

void SpeedTestClient::tick() {
    const double elapsed = m_clock.nsecsElapsed() / 1e9;
    m_window.append({elapsed, m_bytes});
    // O upload do Qt avisa o progresso em rajadas: uma janela maior deixa o número ao vivo mais estável.
    const double windowSeconds = m_phase == Phase::Upload ? 2.0 : 1.0;
    while (m_window.size() > 2 && elapsed - m_window.first().first > windowSeconds) m_window.removeFirst();
    const auto first = m_window.first();
    const double span = elapsed - first.first;
    m_live = span > 0.1 ? (m_bytes - first.second) * 8.0 / span / 1e6 : 0;
    const double warm = qMin(1.2, m_seconds * 0.25);   // os primeiros instantes (partida lenta do TCP) não entram na média
    if (m_warmAt < 0 && elapsed >= warm) { m_warmAt = elapsed; m_warmBytes = m_bytes; }
    const double base = m_phase == Phase::Download ? 0.1 : 0.55;
    m_progress = base + 0.45 * qMin(1.0, elapsed / m_seconds);
    emit changed();
    if (elapsed >= m_seconds) endTransfer();
}

void SpeedTestClient::endTransfer() {
    m_tick.stop();
    const double elapsed = m_clock.nsecsElapsed() / 1e9;
    const double window = elapsed - m_warmAt;
    const qint64 bytes = m_bytes - m_warmBytes;
    abortReplies();
    const Phase phase = m_phase;
    if (m_warmAt < 0 || window < 0.2 || bytes <= 0) {
        finish(phase == Phase::Download ? "O servidor de teste não enviou dados." : "O servidor de teste não recebeu dados.");
        return;
    }
    const double mbps = bytes * 8.0 / window / 1e6;
    if (phase == Phase::Download) { m_download = mbps; beginTransfer(Phase::Upload); }
    else { m_upload = mbps; finish({}); }
}

void SpeedTestClient::abortReplies() {
    if (m_pingReply) { m_pingReply->disconnect(this); m_pingReply->abort(); m_pingReply->deleteLater(); }
    for (const auto &reply : std::as_const(m_replies)) {
        if (!reply) continue;
        reply->disconnect(this);
        reply->abort();
        reply->deleteLater();
    }
    m_replies.clear(); m_sent.clear();
}

void SpeedTestClient::finish(const QString &error) {
    ++m_generation;
    m_tick.stop();
    abortReplies();
    m_running = false; m_phase = Phase::Idle; m_live = 0; m_error = error;
    if (error.isEmpty()) {
        m_progress = 1;
        m_history.prepend(QVariantMap{{"time", QDateTime::currentSecsSinceEpoch()}, {"ping", m_ping}, {"jitter", m_jitter},
                                      {"down", m_download}, {"up", m_upload}, {"server", m_server}});
        while (m_history.size() > HistoryLimit) m_history.removeLast();
        saveHistory();
    } else {
        m_progress = 0;
    }
    emit changed();
    emit finished(error.isEmpty());
}

// ── Histórico ─────────────────────────────────────────────────────────────
QString SpeedTestClient::historyPath() const {
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/plasdria/speedtest.json";
}

void SpeedTestClient::saveHistory() {
    QJsonArray array;
    for (const auto &entry : std::as_const(m_history)) array.append(QJsonObject::fromVariantMap(entry.toMap()));
    QDir().mkpath(QFileInfo(historyPath()).absolutePath());
    QSaveFile out(historyPath());
    if (!out.open(QIODevice::WriteOnly)) return;
    out.write(QJsonDocument(array).toJson(QJsonDocument::Compact));
    out.commit();
    QFile::setPermissions(historyPath(), QFileDevice::ReadOwner | QFileDevice::WriteOwner);
}

void SpeedTestClient::loadHistory() {
    QFile in(historyPath());
    if (!in.open(QIODevice::ReadOnly)) return;
    for (const auto &value : QJsonDocument::fromJson(in.readAll()).array()) {
        const QJsonObject o = value.toObject();
        if (!o.contains("down") || !o.contains("time")) continue;
        m_history.append(o.toVariantMap());
        if (m_history.size() >= HistoryLimit) break;
    }
}
