#include <QtDBus>
#include <QtTest>
#include "../native/dashboardclient.h"

// Servidor de notificações de mentira (org.freedesktop.Notifications) para ver o que o Plasdria envia
// e simular o clique em um botão.
class FakeNotifications : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Notifications")
public:
    QList<QVariantList> received;
public slots:
    uint Notify(const QString &app, uint replaces, const QString &icon, const QString &summary, const QString &body,
                const QStringList &actions, const QVariantMap &hints, int timeout) {
        received.append({app, replaces, icon, summary, body, actions, timeout});
        Q_UNUSED(hints)
        return 40 + received.size();
    }
signals:
    void ActionInvoked(uint id, const QString &actionKey);
    void NotificationClosed(uint id, uint reason);
};

class DashboardClientTest : public QObject {
    Q_OBJECT
    FakeNotifications m_server;
private slots:
    void initTestCase() {
        auto bus = QDBusConnection::sessionBus();
        QVERIFY(bus.isConnected());
        QVERIFY(bus.registerService("org.freedesktop.Notifications"));
        QVERIFY(bus.registerObject("/org/freedesktop/Notifications", &m_server, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
    }
    void plainNotificationHasNoButtons() {
        m_server.received.clear();
        DashboardClient client;
        client.notify("Título", "Corpo");
        QTRY_COMPARE(m_server.received.size(), 1);
        QCOMPARE(m_server.received[0][3].toString(), QString("Título"));
        QVERIFY(m_server.received[0][5].toStringList().isEmpty());
    }
    void buttonClickIsReportedWithItsTag() {
        m_server.received.clear();
        DashboardClient client;
        QSignalSpy spy(&client, &DashboardClient::notificationAction);
        client.notifyAction("Bateria baixa", "18%", "low", {"open", "Ver", "mute", "Silenciar 1 h"});
        QTRY_COMPARE(m_server.received.size(), 1);
        QCOMPARE(m_server.received[0][5].toStringList(), (QStringList{"open", "Ver", "mute", "Silenciar 1 h"}));
        QTest::qWait(200);   // deixa a resposta do Notify chegar e registrar o número do aviso
        emit m_server.ActionInvoked(41, "mute");
        QTRY_COMPARE(spy.size(), 1);
        QCOMPARE(spy[0][0].toString(), QString("low"));
        QCOMPARE(spy[0][1].toString(), QString("mute"));
    }
    void closedOrForeignNotificationsAreIgnored() {
        m_server.received.clear();
        DashboardClient client;
        QSignalSpy spy(&client, &DashboardClient::notificationAction);
        client.notifyAction("A", "b", "disk", {"open", "Ver"});
        QTRY_COMPARE(m_server.received.size(), 1);
        QTest::qWait(200);
        emit m_server.ActionInvoked(9999, "open");          // aviso de outro programa
        emit m_server.NotificationClosed(41, 2);            // este fechou sem clique
        emit m_server.ActionInvoked(41, "open");            // clique atrasado em aviso já fechado
        QTest::qWait(300);
        QCOMPARE(spy.size(), 0);
    }
};
QTEST_MAIN(DashboardClientTest)
#include "dashboardclient_test.moc"
