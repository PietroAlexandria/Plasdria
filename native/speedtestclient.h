#pragma once

#include <QByteArray>
#include <QElapsedTimer>
#include <QHash>
#include <QList>
#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QVariantList>

class QNetworkReply;

// Teste de velocidade: latência, download e upload contra os servidores públicos de medição da Cloudflare
// (speed.cloudflare.com). Só roda quando o usuário pede e consome dados: algo como 50 a 300 MB em uma conexão rápida.
class SpeedTestClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool running READ running NOTIFY changed)
    Q_PROPERTY(QString phase READ phase NOTIFY changed)               // "", "ping", "download", "upload"
    Q_PROPERTY(double progress READ progress NOTIFY changed)          // 0..1 do teste inteiro
    Q_PROPERTY(double liveMbps READ liveMbps NOTIFY changed)          // velocidade instantânea na fase atual
    Q_PROPERTY(double pingMs READ pingMs NOTIFY changed)              // -1 enquanto não medido
    Q_PROPERTY(double jitterMs READ jitterMs NOTIFY changed)
    Q_PROPERTY(double downloadMbps READ downloadMbps NOTIFY changed)
    Q_PROPERTY(double uploadMbps READ uploadMbps NOTIFY changed)
    Q_PROPERTY(QString server READ server NOTIFY changed)             // ex.: "Cloudflare · GRU"
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QVariantList history READ history NOTIFY changed)      // [{time, ping, jitter, down, up, server}], do mais novo ao mais antigo
    // Ajustáveis (os testes automatizados apontam para um servidor local e encurtam as fases).
    Q_PROPERTY(QString baseUrl READ baseUrl WRITE setBaseUrl NOTIFY changed)
    Q_PROPERTY(double testSeconds READ testSeconds WRITE setTestSeconds NOTIFY changed)
    Q_PROPERTY(int streams READ streams WRITE setStreams NOTIFY changed)
public:
    explicit SpeedTestClient(QObject *parent = nullptr);

    bool running() const { return m_running; }
    QString phase() const;
    double progress() const { return m_progress; }
    double liveMbps() const { return m_live; }
    double pingMs() const { return m_ping; }
    double jitterMs() const { return m_jitter; }
    double downloadMbps() const { return m_download; }
    double uploadMbps() const { return m_upload; }
    QString server() const { return m_server; }
    QString error() const { return m_error; }
    QVariantList history() const { return m_history; }
    QString baseUrl() const { return m_baseUrl; }
    void setBaseUrl(const QString &url) { m_baseUrl = url; emit changed(); }
    double testSeconds() const { return m_seconds; }
    void setTestSeconds(double s) { m_seconds = qBound(0.5, s, 60.0); emit changed(); }
    int streams() const { return m_streams; }
    void setStreams(int n) { m_streams = qBound(1, n, 6); emit changed(); }

    Q_INVOKABLE void start();
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void clearHistory();

signals:
    void changed();
    void finished(bool ok);

private:
    enum class Phase { Idle, Ping, Download, Upload };
    void pingOnce();
    void beginTransfer(Phase phase);
    void spawn(int generation);
    void tick();
    void endTransfer();
    void finish(const QString &error);
    void abortReplies();
    void saveHistory();
    void loadHistory();
    QString historyPath() const;

    QNetworkAccessManager m_net;
    QTimer m_tick;
    bool m_running = false;
    Phase m_phase = Phase::Idle;
    QString m_baseUrl = QStringLiteral("https://speed.cloudflare.com");
    double m_seconds = 8;
    int m_streams = 6;
    double m_progress = 0, m_live = 0, m_ping = -1, m_jitter = -1, m_download = -1, m_upload = -1;
    QString m_server, m_error;
    QVariantList m_history;
    // latência
    QList<double> m_pingSamples;
    QPointer<QNetworkReply> m_pingReply;
    QElapsedTimer m_pingClock;
    // transferência
    QElapsedTimer m_clock;
    qint64 m_bytes = 0, m_warmBytes = 0;
    double m_warmAt = -1;
    QList<QPair<double, qint64>> m_window;   // (segundos, bytes) para a velocidade instantânea
    QList<QPointer<QNetworkReply>> m_replies;
    QHash<QNetworkReply *, qint64> m_sent;
    QByteArray m_payload;
    int m_failures = 0;
    int m_generation = 0;   // invalida respostas de fases ou testes anteriores
};
