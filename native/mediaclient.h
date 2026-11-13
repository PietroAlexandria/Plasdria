#pragma once

#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QUrl>

class QNetworkAccessManager;

// Player de mídia ativo via MPRIS (Spotify, navegadores, VLC, Elisa…).
// Lembra a última música (com a capa guardada em cache) para mostrar e retomar
// mesmo com o player fechado ou sem internet.
class MediaClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY changed)     // há algo para mostrar (ao vivo ou lembrado)
    Q_PROPERTY(bool live READ live NOTIFY changed)               // o player está aberto
    Q_PROPERTY(bool launching READ launching NOTIFY changed)     // abrindo o player para retomar
    Q_PROPERTY(bool playing READ playing NOTIFY changed)
    Q_PROPERTY(QString title READ title NOTIFY changed)
    Q_PROPERTY(QString artist READ artist NOTIFY changed)
    Q_PROPERTY(QString album READ album NOTIFY changed)
    Q_PROPERTY(QUrl artUrl READ artUrl NOTIFY changed)
    Q_PROPERTY(QString player READ player NOTIFY changed)         // o programa (Firefox, VLC, Spotify…)
    Q_PROPERTY(QString source READ source NOTIFY changed)         // de onde vem (YouTube, Netflix…); sem site conhecido, é o programa
    Q_PROPERTY(bool isVideo READ isVideo NOTIFY changed)          // vídeo (YouTube, Netflix, arquivo .mkv…) e não música
    // Áudio de programas que não falam MPRIS (jogos, Discord…): só mostra o que está tocando, sem controles.
    Q_PROPERTY(bool external READ external NOTIFY changed)
    Q_PROPERTY(QString externalApp READ externalApp NOTIFY changed)
    Q_PROPERTY(QString externalTitle READ externalTitle NOTIFY changed)
    Q_PROPERTY(bool isSpotify READ isSpotify NOTIFY changed)
    Q_PROPERTY(bool spotifyInstalled READ spotifyInstalled CONSTANT)
    Q_PROPERTY(double position READ position NOTIFY positionChanged)
    Q_PROPERTY(double length READ length NOTIFY changed)
    Q_PROPERTY(bool canGoNext READ canGoNext NOTIFY changed)
    Q_PROPERTY(bool canGoPrevious READ canGoPrevious NOTIFY changed)
    Q_PROPERTY(bool canSeek READ canSeek NOTIFY changed)
    Q_PROPERTY(bool hasShuffle READ hasShuffle NOTIFY changed)
    Q_PROPERTY(bool shuffle READ shuffle NOTIFY changed)
    Q_PROPERTY(QString loopStatus READ loopStatus NOTIFY changed)  // "", "None", "Track", "Playlist"
    Q_PROPERTY(double volume READ volume NOTIFY changed)           // -1 se o player não informa
public:
    explicit MediaClient(QObject *parent = nullptr);
    bool available() const { return live() || !m_title.isEmpty(); }
    bool live() const { return !m_service.isEmpty(); }
    bool launching() const { return m_pendingResume; }
    bool playing() const { return live() && m_status == QLatin1String("Playing"); }
    QString title() const { return m_title; }
    QString artist() const { return m_artist; }
    QString album() const { return m_album; }
    QUrl artUrl() const;
    QString player() const { return m_player; }
    QString source() const { return m_source.isEmpty() ? m_player : m_source; }
    bool isVideo() const { return m_video; }
    bool external() const { return !m_extApp.isEmpty(); }
    QString externalApp() const { return m_extApp; }
    QString externalTitle() const { return m_extTitle; }
    bool isSpotify() const { return m_entry == QLatin1String("spotify"); }
    bool spotifyInstalled() const;
    double position() const;
    double length() const { return m_length; }
    bool canGoNext() const { return live() && m_canNext; }
    bool canGoPrevious() const { return live() && m_canPrevious; }
    bool canSeek() const { return live() && m_canSeek; }
    bool hasShuffle() const { return live() && m_hasShuffle; }
    bool shuffle() const { return m_shuffle; }
    QString loopStatus() const { return live() ? m_loop : QString(); }
    double volume() const { return live() ? m_volume : -1; }

    Q_INVOKABLE void playPause();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void seek(double seconds);
    Q_INVOKABLE void raise();
    Q_INVOKABLE void setShuffle(bool on);
    Q_INVOKABLE void cycleLoop();
    Q_INVOKABLE void setVolume(double value);
    Q_INVOKABLE void openSpotify();
    Q_INVOKABLE void forget();

signals:
    void changed();
    void positionChanged();

private:
    void poll();
    void startAudioWatch();
    void listAudioStreams();
    void applyAudioStreams(const QByteArray &json);
    void apply(const QString &service, const QVariantMap &props);
    void playerGone();
    void call(const QString &method, const QVariantList &args = {});
    void setPlayerProperty(const QString &name, const QVariant &value);
    void launch(const QString &entry);
    void resumeOn(const QString &service);
    void cacheArt();
    void save();
    void restore();
    QString statePath() const;
    QString artDir() const;
    QString spotifyCommand() const;

    QTimer m_timer, m_tick;
    QNetworkAccessManager *m_net = nullptr;
    QString m_service, m_status, m_title, m_artist, m_album, m_player, m_entry, m_trackId, m_uri;
    QUrl m_artUrl;        // endereço original da capa
    QString m_artFile;    // cópia local da capa
    QString m_artLoading;
    QString m_loop;
    double m_length = 0, m_position = 0, m_volume = -1;
    qint64 m_positionAt = 0, m_savedAt = 0, m_resumeSince = 0;
    bool m_canNext = false, m_canPrevious = false, m_canSeek = false, m_hasShuffle = false, m_shuffle = false;
    bool m_pendingResume = false, m_resumeOpened = false;
    QString m_savedKey;
    QString m_source, m_extApp, m_extTitle;
    bool m_video = false;
    QProcess *m_watch = nullptr;     // pactl subscribe: avisa quando um programa começa ou para de tocar
    QTimer m_listDebounce;
    bool m_watchGaveUp = false;
};
