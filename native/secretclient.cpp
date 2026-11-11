#include "secretclient.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMetaType>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusVariant>
#include <QMap>

namespace {
const QString Service = QStringLiteral("org.freedesktop.secrets");
const QString ServicePath = QStringLiteral("/org/freedesktop/secrets");
const QString ServiceInterface = QStringLiteral("org.freedesktop.Secret.Service");
const QString CollectionInterface = QStringLiteral("org.freedesktop.Secret.Collection");
const QString ItemInterface = QStringLiteral("org.freedesktop.Secret.Item");
const QString DefaultCollection = QStringLiteral("/org/freedesktop/secrets/aliases/default");
constexpr int TimeoutMs = 3000;

using Attributes = QMap<QString, QString>;

// (oayays): sessão, parâmetros, valor, tipo de conteúdo.
struct SecretValue {
    QDBusObjectPath session;
    QByteArray parameters;
    QByteArray value;
    QString contentType;
};
QDBusArgument &operator<<(QDBusArgument &arg, const SecretValue &s) {
    arg.beginStructure(); arg << s.session << s.parameters << s.value << s.contentType; arg.endStructure(); return arg;
}
const QDBusArgument &operator>>(const QDBusArgument &arg, SecretValue &s) {
    arg.beginStructure(); arg >> s.session >> s.parameters >> s.value >> s.contentType; arg.endStructure(); return arg;
}
}
Q_DECLARE_METATYPE(SecretValue)
Q_DECLARE_METATYPE(Attributes)

namespace {
void registerTypes() {
    static bool done = false;
    if (done) return;
    done = true;
    qDBusRegisterMetaType<SecretValue>();
    qDBusRegisterMetaType<Attributes>();
    qDBusRegisterMetaType<QList<QDBusObjectPath>>();
}

QDBusMessage call(const QString &path, const QString &interface, const QString &method, const QVariantList &args = {}) {
    auto message = QDBusMessage::createMethodCall(Service, path, interface, method);
    message.setArguments(args);
    return QDBusConnection::sessionBus().call(message, QDBus::Block, TimeoutMs);
}

Attributes attributesFor(const QString &key) { return {{"application", "plasdria"}, {"key", key}}; }

// Sessão "plain": o segredo trafega sem criptografia pelo D-Bus da sessão do próprio usuário.
QString openSession() {
    const auto reply = call(ServicePath, ServiceInterface, "OpenSession", {QStringLiteral("plain"), QVariant::fromValue(QDBusVariant(QString()))});
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().size() < 2) return {};
    return reply.arguments().at(1).value<QDBusObjectPath>().path();
}
void closeSession(const QString &session) { if (!session.isEmpty()) call(session, "org.freedesktop.Secret.Session", "Close"); }

// Caminho do item (desbloqueado) com a chave, ou "".
QString findItem(const QString &key) {
    const auto reply = call(ServicePath, ServiceInterface, "SearchItems", {QVariant::fromValue(attributesFor(key))});
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().size() < 2) return {};
    QList<QDBusObjectPath> unlocked;
    reply.arguments().at(0).value<QDBusArgument>() >> unlocked;
    return unlocked.isEmpty() ? QString() : unlocked.first().path();
}
}

SecretClient::SecretClient(QObject *parent) : QObject(parent) { registerTypes(); }

bool SecretClient::available() {
    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected() || !bus.interface() || !bus.interface()->isServiceRegistered(Service)) return false;
    const auto reply = call(DefaultCollection, "org.freedesktop.DBus.Properties", "Get", {CollectionInterface, QStringLiteral("Locked")});
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) return false;
    return !reply.arguments().first().value<QDBusVariant>().variant().toBool();
}

QString SecretClient::read(const QString &key) {
    if (!available()) return {};
    const QString item = findItem(key);
    if (item.isEmpty()) return {};
    const QString session = openSession();
    if (session.isEmpty()) return {};
    const auto reply = call(item, ItemInterface, "GetSecret", {QVariant::fromValue(QDBusObjectPath(session))});
    closeSession(session);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) return {};
    SecretValue secret;
    reply.arguments().first().value<QDBusArgument>() >> secret;
    return QString::fromUtf8(secret.value);
}

bool SecretClient::write(const QString &key, const QString &value) {
    if (!available()) return false;
    if (value.isEmpty()) {   // apagar
        const QString item = findItem(key);
        if (item.isEmpty()) return true;
        return call(item, ItemInterface, "Delete").type() == QDBusMessage::ReplyMessage;
    }
    const QString session = openSession();
    if (session.isEmpty()) return false;
    SecretValue secret{QDBusObjectPath(session), {}, value.toUtf8(), QStringLiteral("text/plain")};
    const QVariantMap properties{
        {"org.freedesktop.Secret.Item.Label", QStringLiteral("Plasdria · %1").arg(key)},
        {"org.freedesktop.Secret.Item.Attributes", QVariant::fromValue(attributesFor(key))}};
    const auto reply = call(DefaultCollection, CollectionInterface, "CreateItem",
                            {properties, QVariant::fromValue(secret), true});
    closeSession(session);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().size() < 2) return false;
    // Se o cofre pedir confirmação (prompt), o segredo não foi guardado.
    return reply.arguments().at(1).value<QDBusObjectPath>().path() == QLatin1String("/");
}
