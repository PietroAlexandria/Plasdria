#include <QtTest>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusObjectPath>
#include <QImage>

#include "../native/mediaclient.h"

// Um "Spotify" falso no D-Bus da sessão de teste (rodar com dbus-run-session).
class FakePlayer : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2.Player")
    Q_PROPERTY(QString PlaybackStatus MEMBER status)
    Q_PROPERTY(QVariantMap Metadata MEMBER metadata)
    Q_PROPERTY(qlonglong Position MEMBER position)
    Q_PROPERTY(bool CanGoNext MEMBER yes)
    Q_PROPERTY(bool CanGoPrevious MEMBER yes)
    Q_PROPERTY(bool CanSeek MEMBER yes)
    Q_PROPERTY(bool Shuffle MEMBER shuffle)
    Q_PROPERTY(QString LoopStatus MEMBER loop)
    Q_PROPERTY(double Volume MEMBER volume)
public:
    QString status = "Playing", loop = "None";
    QVariantMap metadata;
    qlonglong position = 0;
    bool yes = true, shuffle = false;
    double volume = 0.8;
    QStringList calls;
    void setTrack(const QString &id, const QString &title, const QString &art) {
        metadata = {{"mpris:trackid", QVariant::fromValue(QDBusObjectPath("/com/spotify/track/" + id))},
                    {"xesam:title", title}, {"xesam:artist", QStringList{"Artista"}}, {"xesam:album", "Álbum"},
                    {"mpris:length", qlonglong(200'000'000)}, {"mpris:artUrl", art},
                    {"xesam:url", "https://open.spotify.com/track/" + id}};
    }
public slots:
    void PlayPause() { calls << "PlayPause"; status = status == "Playing" ? "Paused" : "Playing"; }
    void Play() { calls << "Play"; status = "Playing"; }
    void OpenUri(const QString &uri) { calls << "OpenUri " + uri; }
    void SetPosition(const QDBusObjectPath &track, qlonglong at) { calls << QString("SetPosition %1 %2").arg(track.path()).arg(at / 1000000); position = at; }
};

class MediaClientTest : public QObject {
    Q_OBJECT
    QTemporaryDir m_home;
    QString m_art;
    FakePlayer m_player;
    QString Service = "org.mpris.MediaPlayer2.spotify";
    QString m_streams, m_events;   // arquivos que o "pactl" de mentira lê

    void publish() {
        auto bus = QDBusConnection::sessionBus();
        QVERIFY(bus.registerObject("/org/mpris/MediaPlayer2", &m_player, QDBusConnection::ExportAllContents));
        QVERIFY(bus.registerService(Service));
    }
    void unpublish() {
        auto bus = QDBusConnection::sessionBus();
        bus.unregisterService(Service);
        bus.unregisterObject("/org/mpris/MediaPlayer2");
    }

private slots:
    void initTestCase() {
        QVERIFY(QDBusConnection::sessionBus().isConnected());
        qputenv("XDG_DATA_HOME", (m_home.path() + "/data").toUtf8());
        qputenv("XDG_CACHE_HOME", (m_home.path() + "/cache").toUtf8());
        qputenv("PLASDRIA_SPOTIFY_COMMAND", "true");   // "abrir o Spotify" não faz nada no teste
        // "pactl" de mentira: `subscribe` acompanha um arquivo de eventos e `list` devolve um JSON escolhido pelo teste.
        QVERIFY(QDir().mkpath(m_home.path() + "/bin"));
        m_streams = m_home.path() + "/streams.json"; m_events = m_home.path() + "/events.txt";
        QFile events(m_events); QVERIFY(events.open(QIODevice::WriteOnly)); events.close();
        QFile script(m_home.path() + "/bin/pactl");
        QVERIFY(script.open(QIODevice::WriteOnly));
        script.write("#!/bin/bash\nif [ \"$1\" = subscribe ]; then exec tail -n0 -F \"$PLASDRIA_FAKE_EVENTS\"; fi\ncat \"$PLASDRIA_FAKE_STREAMS\" 2>/dev/null\n");
        script.close();
        QVERIFY(script.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner));
        qputenv("PATH", (m_home.path() + "/bin:" + qEnvironmentVariable("PATH")).toUtf8());
        qputenv("PLASDRIA_FAKE_STREAMS", m_streams.toUtf8());
        qputenv("PLASDRIA_FAKE_EVENTS", m_events.toUtf8());
        m_art = m_home.path() + "/capa.png";
        QImage image(8, 8, QImage::Format_RGB32); image.fill(Qt::green);
        QVERIFY(image.save(m_art));
    }

    void remembersTrackAfterPlayerCloses() {
        m_player.setTrack("ABC123", "Música de teste", QUrl::fromLocalFile(m_art).toString());
        m_player.position = 42'000'000;
        publish();
        MediaClient client;
        QTRY_VERIFY_WITH_TIMEOUT(client.live() && client.title() == "Música de teste", 5000);
        QCOMPARE(client.artist(), QString("Artista"));
        QVERIFY(client.isSpotify());
        QCOMPARE(client.volume(), 0.8);
        QCOMPARE(client.loopStatus(), QString("None"));
        // A capa vira uma cópia local, que sobrevive ao arquivo original.
        QTRY_VERIFY(client.artUrl().isLocalFile() && client.artUrl().toLocalFile().contains("/cache/plasdria/art/"));

        m_player.status = "Paused";
        QTest::qWait(1700);
        unpublish();
        QFile::remove(m_art);
        QTRY_VERIFY_WITH_TIMEOUT(!client.live(), 5000);
        QVERIFY(client.available());
        QVERIFY(!client.playing());
        QCOMPARE(client.title(), QString("Música de teste"));
        QVERIFY(QFileInfo::exists(client.artUrl().toLocalFile()));
        QVERIFY(qAbs(client.position() - 42) < 3);

        // Um widget novo (ex.: Plasma reiniciado) ainda lembra a música, sem player nem internet.
        MediaClient again;
        QVERIFY(again.available());
        QVERIFY(!again.live());
        QCOMPARE(again.title(), QString("Música de teste"));
        QVERIFY(QFileInfo::exists(again.artUrl().toLocalFile()));
    }

    void resumesWhereItStopped() {
        MediaClient client;
        QVERIFY(!client.live());
        QCOMPARE(client.title(), QString("Música de teste"));
        m_player.calls.clear();
        m_player.metadata.clear();
        m_player.status = "Stopped";
        m_player.position = 0;

        client.playPause();          // abre o "Spotify"
        QVERIFY(client.launching());
        publish();                   // o Spotify aparece no D-Bus, ainda sem música
        QTRY_VERIFY_WITH_TIMEOUT(m_player.calls.contains("OpenUri spotify:track:ABC123"), 8000);
        m_player.setTrack("ABC123", "Música de teste", "");
        m_player.status = "Playing";
        QTRY_VERIFY_WITH_TIMEOUT(m_player.calls.contains("SetPosition /com/spotify/track/ABC123 42"), 8000);
        QTRY_VERIFY_WITH_TIMEOUT(!client.launching() && client.live() && client.playing(), 5000);
        unpublish();
    }

    void setStreams(const QByteArray &json) {
        QFile f(m_streams); QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Truncate)); f.write(json); f.close();
        QFile e(m_events); QVERIFY(e.open(QIODevice::WriteOnly | QIODevice::Append)); e.write("Event 'change' on sink-input #7\n"); e.close();
    }
    void publishAs(const QString &service, const QString &url, bool music = false) {
        Service = service;
        m_player.status = "Playing";
        m_player.metadata = {{"mpris:trackid", QVariant::fromValue(QDBusObjectPath("/x/1"))}, {"xesam:title", "Algo"},
                             {"xesam:artist", QStringList{music ? "Banda" : "Canal"}}, {"xesam:url", url}, {"mpris:length", qlonglong(120'000'000)}};
        publish();
    }

    void recognizesYouTubeInTheBrowser() {
        publishAs("org.mpris.MediaPlayer2.firefox.instance_1_23", "https://www.youtube.com/watch?v=abc");
        MediaClient client;
        QTRY_VERIFY_WITH_TIMEOUT(client.live() && client.title() == "Algo", 5000);
        QCOMPARE(client.source(), QString("YouTube"));
        QCOMPARE(client.player(), QString("Firefox"));
        QVERIFY(client.isVideo());
        unpublish();
    }
    void recognizesMusicSitesAndVideoFiles() {
        publishAs("org.mpris.MediaPlayer2.chromium.instance9", "https://music.youtube.com/watch?v=abc", true);
        {
            MediaClient client;
            QTRY_VERIFY_WITH_TIMEOUT(client.live() && client.title() == "Algo", 5000);
            QCOMPARE(client.source(), QString("YouTube Music"));
            QVERIFY(!client.isVideo());
        }
        unpublish();
        publishAs("org.mpris.MediaPlayer2.vlc", "file:///home/x/filme.mkv");
        {
            MediaClient client;
            QTRY_VERIFY_WITH_TIMEOUT(client.live() && client.title() == "Algo", 5000);
            QCOMPARE(client.source(), QString("VLC"));   // sem site, a origem é o programa
            QVERIFY(client.isVideo());
        }
        unpublish();
        publishAs("org.mpris.MediaPlayer2.vlc", "file:///home/x/musica.flac", true);
        {
            MediaClient client;
            QTRY_VERIFY_WITH_TIMEOUT(client.live() && client.title() == "Algo", 5000);
            QVERIFY(!client.isVideo());
        }
        unpublish();
    }
    void showsAudioFromProgramsWithoutPlayer() {
        setStreams("[]");
        MediaClient client;
        QVERIFY(!client.external());
        // Jogo tocando, e um som de notificação (ignorado)
        setStreams(R"([{"corked":false,"mute":false,"properties":{"application.name":"Discord","media.name":"Playback","media.role":"event"}},
                       {"corked":false,"mute":false,"properties":{"application.name":"Meu Jogo","media.name":"Trilha sonora"}}])");
        QTRY_VERIFY_WITH_TIMEOUT(client.external(), 6000);
        QCOMPARE(client.externalApp(), QString("Meu Jogo"));
        QCOMPARE(client.externalTitle(), QString("Trilha sonora"));
        // Título genérico some e fica só o programa
        setStreams(R"([{"corked":false,"mute":false,"properties":{"application.name":"Meu Jogo","media.name":"Playback"}}])");
        QTRY_VERIFY_WITH_TIMEOUT(client.externalTitle().isEmpty() && client.external(), 6000);
        // Pausado ou mudo não conta; sem fluxos, some
        setStreams(R"([{"corked":true,"mute":false,"properties":{"application.name":"Meu Jogo"}},{"corked":false,"mute":true,"properties":{"application.name":"Outro"}}])");
        QTRY_VERIFY_WITH_TIMEOUT(!client.external(), 6000);
    }

    void forgetClearsRememberedTrack() {
        MediaClient client;
        QTRY_VERIFY_WITH_TIMEOUT(!client.live(), 5000);
        QVERIFY(client.available());
        client.forget();
        QVERIFY(!client.available());
        MediaClient again;
        QVERIFY(!again.available());
    }
};

QTEST_GUILESS_MAIN(MediaClientTest)
#include "mediaclient_test.moc"
