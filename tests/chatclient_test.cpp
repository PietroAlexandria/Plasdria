#include <QtTest>
#include <QtQml>
#include <QAbstractItemModel>
#include <QGuiApplication>
#include <QImage>
#include <memory>

// Testa o cliente de conversa contra tests/fake_claude.py, sem chamadas reais ao Claude.
class ChatClientTest : public QObject {
    Q_OBJECT
    QTemporaryDir m_data;
    QString m_log, m_project;
    std::unique_ptr<QQmlEngine> m_engine;
    std::unique_ptr<QObject> m_client;

    QObject *createClient() {
        QQmlComponent component(m_engine.get());
        const auto base = QUrl::fromLocalFile(QStringLiteral(PRAGUS_PROJECT_ROOT) + "/package/contents/ui/chatclient-test.qml");
        component.setData("import QtQml\nimport \"bridge\" as Backend\nBackend.ClaudeClient {}\n", base);
        QObject *client = component.create();
        if (!client) qWarning() << component.errors();
        if (client) {
            client->setProperty("executable", QStringLiteral(PRAGUS_PROJECT_ROOT) + "/tests/fake_claude.py");
            client->setProperty("antigravityExecutable", QStringLiteral(PRAGUS_PROJECT_ROOT) + "/tests/fake_agy.py");
        }
        return client;
    }
    void startClient() {
        m_engine = std::make_unique<QQmlEngine>();
        m_client.reset(createClient());
        QVERIFY(m_client);
        QVERIFY(invoke("start"));
        QTRY_VERIFY_WITH_TIMEOUT(flag("ready") || !text("error").isEmpty(), 10000);
        QTRY_VERIFY_WITH_TIMEOUT(!flag("historyBusy"), 5000);
        QTRY_VERIFY_WITH_TIMEOUT(!flag("conversationLoading"), 5000);
    }
    bool flag(const char *property) const { return m_client->property(property).toBool(); }
    QString text(const char *property) const { return m_client->property(property).toString(); }
    QString threadId() const { return text("threadId"); }
    QAbstractItemModel *messages() const { return m_client->property("messages").value<QAbstractItemModel *>(); }
    QVariantList history() const { return m_client->property("history").toList(); }
    bool invoke(const char *method) const { return QMetaObject::invokeMethod(m_client.get(), method); }
    bool callBool(const char *method, const QVariant &argument) const {
        bool accepted = false;
        bool invoked = false;
        if (argument.typeId() == QMetaType::QUrl)
            invoked = QMetaObject::invokeMethod(m_client.get(), method, Q_RETURN_ARG(bool, accepted), Q_ARG(QUrl, argument.toUrl()));
        else
            invoked = QMetaObject::invokeMethod(m_client.get(), method, Q_RETURN_ARG(bool, accepted), Q_ARG(QString, argument.toString()));
        return invoked && accepted;
    }
    bool load(const QString &id) const { return callBool("loadConversation", id); }
    bool send(const QString &value) const { return callBool("send", value); }
    QList<QJsonObject> entries(const QString &key) const {
        QFile file(m_log);
        if (!file.open(QIODevice::ReadOnly)) return {};
        QList<QJsonObject> rows;
        while (!file.atEnd()) {
            const auto object = QJsonDocument::fromJson(file.readLine()).object();
            if (object.contains(key)) rows.append(object);
        }
        return rows;
    }
    // Processos de resposta (os que receberam uma mensagem do usuário).
    QList<QJsonObject> turnArgs() const {
        QList<QJsonObject> rows;
        for (const auto &row : entries("argv")) if (row["argv"].toArray().contains("--include-partial-messages")) rows.append(row);
        return rows;
    }
    QJsonArray lastUserContent() const {
        QJsonArray content;
        for (const auto &row : entries("stdin")) {
            const auto message = row["stdin"].toObject();
            if (message["type"] == "user") content = message["message"].toObject()["content"].toArray();
        }
        return content;
    }
    static QString argAfter(const QJsonArray &argv, const QString &name) {
        for (int i = 0; i + 1 < argv.size(); ++i) if (argv[i] == name) return argv[i + 1].toString();
        return {};
    }
    void resetLog() const { QFile file(m_log); QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate)); }
    QString allBodies() const {
        QStringList bodies;
        auto *model = messages();
        for (int i = 0; i < model->rowCount(); ++i) bodies.append(model->data(model->index(i, 0), Qt::UserRole + 2).toString());
        return bodies.join('\n');
    }
    void writeSession(const QString &folder, const QString &id, const QList<QJsonObject> &records) {
        const QString dir = m_data.path() + "/claude/projects/" + folder;
        QVERIFY(QDir().mkpath(dir));
        QFile file(dir + "/" + id + ".jsonl");
        QVERIFY(file.open(QIODevice::WriteOnly));
        for (const auto &r : records) file.write(QJsonDocument(r).toJson(QJsonDocument::Compact) + "\n");
    }
    QJsonObject user(const QJsonValue &content, const QString &cwd, const QJsonObject &extra = {}) {
        QJsonObject o{{"type", "user"}, {"cwd", cwd}, {"entrypoint", "cli"}, {"uuid", QUuid::createUuid().toString(QUuid::WithoutBraces)},
            {"message", QJsonObject{{"role", "user"}, {"content", content}}}};
        for (auto i = extra.begin(); i != extra.end(); ++i) o.insert(i.key(), i.value());
        return o;
    }
    QJsonObject assistant(const QString &id, const QString &body) {
        return {{"type", "assistant"}, {"uuid", QUuid::createUuid().toString(QUuid::WithoutBraces)},
            {"message", QJsonObject{{"id", id}, {"role", "assistant"}, {"model", "claude-sonnet"}, {"content", QJsonArray{QJsonObject{{"type", "text"}, {"text", body}}}}}}};
    }
private slots:
    void init() {
        QVERIFY(m_data.isValid());
        m_client.reset(); m_engine.reset();
        QDir(m_data.path() + "/data").removeRecursively();
        QDir(m_data.path() + "/claude").removeRecursively();
        QDir(m_data.path() + "/antigravity").removeRecursively();
        m_project = m_data.path() + "/projeto";
        QVERIFY(QDir().mkpath(m_project));
        m_log = m_data.path() + "/rpc.jsonl";
        qputenv("XDG_DATA_HOME", (m_data.path() + "/data").toUtf8());
        qputenv("CLAUDE_CONFIG_DIR", (m_data.path() + "/claude").toUtf8());
        qputenv("ANTIGRAVITY_CONFIG_DIR", (m_data.path() + "/antigravity").toUtf8());
        qputenv("PRAGUS_TEST_RPC_LOG", m_log.toUtf8());
        qunsetenv("PRAGUS_FAKE_LOGGED_OUT");
        resetLog();
        const QString folder = QString(m_project).replace(QRegularExpression("[^A-Za-z0-9]"), "-");
        writeSession(folder, "saved-chat", {
            QJsonObject{{"type", "ai-title"}, {"aiTitle", "Cor preferida"}},
            user("Minha cor preferida é azul.", m_project),
            assistant("m1", "Anotado."),
            user(QJsonArray{QJsonObject{{"type", "tool_result"}, {"content", "saida da ferramenta"}}}, m_project, {{"toolUseResult", "x"}}),
            assistant("m2", "Mais alguma coisa?"),
            user("<system-reminder>interno</system-reminder>", m_project, {{"isMeta", true}}),
        });
        writeSession("C--Users-x", "windows-chat", {user("Conversa do Windows", "C:\\Users\\x")});
        writeSession(folder, "meta-only", {user("<local-command-stdout>ok</local-command-stdout>", m_project)});
        startClient();
    }
    void cleanup() { m_client.reset(); m_engine.reset(); }

    void handshakeListsModelsAndAccount() {
        QVERIFY(flag("ready"));
        const auto models = m_client->property("models").toList();
        QCOMPARE(models.size(), 2);
        QCOMPARE(text("model"), QString("sonnet"));
        QCOMPARE(text("effort"), QString("medium"));
        QCOMPARE(m_client->property("efforts").toStringList(), QStringList({"low", "medium", "high"}));
        QCOMPARE(text("plan"), QString("Claude Pro"));
        const auto probe = entries("argv").first()["argv"].toArray();
        QVERIFY(probe.contains("--no-session-persistence"));
        QCOMPARE(argAfter(probe, "--setting-sources"), QString(""));
    }
    void quotaIsReadWithoutSendingMessages() {
        // A cota vem do get_usage logo ao conectar, sem nenhuma pergunta.
        QTRY_COMPARE_WITH_TIMEOUT(m_client->property("fiveHourUsed").toDouble(), 25.0, 10000);
        QCOMPARE(m_client->property("weeklyUsed").toDouble(), 50.0);
        QCOMPARE(m_client->property("fiveHourReset").toLongLong(), 4102444800LL);
        QCOMPARE(turnArgs().size(), 0);
        bool asked = false;
        for (const auto &row : entries("stdin")) if (row["stdin"].toObject()["request"].toObject()["subtype"] == "get_usage") asked = true;
        QVERIFY(asked);
    }
    void loggedOutAccountAsksForLogin() {
        cleanup();
        qputenv("PRAGUS_FAKE_LOGGED_OUT", "1");
        startClient();
        QVERIFY(!flag("ready"));
        QVERIFY(text("error").contains("login"));
    }
    void historyListsOnlyResumableSessions() {
        QCOMPARE(history().size(), 1);
        const auto row = history().first().toMap();
        QCOMPARE(row["id"].toString(), QString("saved-chat"));
        QCOMPARE(row["title"].toString(), QString("Cor preferida"));
        QCOMPARE(row["source"].toString(), QString("CLI"));
        QVERIFY(!flag("historyHasMore"));
    }
    void resumeRestoresMessagesAndContinuesSameSession() {
        QVERIFY(load("saved-chat"));
        QCOMPARE(threadId(), QString("saved-chat"));
        QCOMPARE(messages()->rowCount(), 2);
        QVERIFY(allBodies().contains("Minha cor preferida é azul."));
        QVERIFY(allBodies().contains("Anotado.\n\nMais alguma coisa?"));
        QVERIFY(!allBodies().contains("saida da ferramenta"));
        QVERIFY(!allBodies().contains("interno"));
        resetLog();
        QVERIFY(send("Qual é minha cor preferida?"));
        QTRY_VERIFY_WITH_TIMEOUT(!flag("busy"), 10000);
        QCOMPARE(text("error"), QString());
        const auto turn = turnArgs();
        QCOMPARE(turn.size(), 1);
        const auto argv = turn.first()["argv"].toArray();
        QCOMPARE(argAfter(argv, "--resume"), QString("saved-chat"));
        QCOMPARE(turn.first()["cwd"].toString(), m_project);
        QCOMPARE(argAfter(argv, "--tools"), QString("Read,Glob,Grep,WebSearch,WebFetch"));
        QCOMPARE(argAfter(argv, "--model"), QString("sonnet"));
        QCOMPARE(argAfter(argv, "--effort"), QString("medium"));
        QVERIFY(argAfter(argv, "--append-system-prompt").contains("Pragus"));
        QCOMPARE(threadId(), QString("saved-chat"));
        QVERIFY(allBodies().endsWith("Resposta: Qual é minha cor preferida?"));
    }
    void missingConversationKeepsCurrentChat() {
        QVERIFY(load("saved-chat"));
        const auto previous = allBodies();
        QVERIFY(load("missing-chat"));
        QCOMPARE(threadId(), QString("saved-chat"));
        QCOMPARE(allBodies(), previous);
        QVERIFY(!text("historyError").isEmpty());
        QVERIFY(load("windows-chat"));
        QCOMPARE(threadId(), QString("saved-chat"));
        QVERIFY(text("historyError").contains("pasta"));
    }
    void newChatStreamsAnswerAndTracksQuota() {
        QVERIFY(send("Olá"));
        QTRY_VERIFY_WITH_TIMEOUT(!flag("busy"), 10000);
        QCOMPARE(text("error"), QString());
        const auto argv = turnArgs().last()["argv"].toArray();
        QVERIFY(!argv.contains("--resume"));
        QVERIFY(!threadId().isEmpty());
        QCOMPARE(messages()->rowCount(), 2);
        QCOMPARE(allBodies(), QString("Olá\nResposta: Olá"));
        QCOMPARE(m_client->property("fiveHourUsed").toDouble(), 25.0);
        QCOMPARE(m_client->property("weeklyUsed").toDouble(), 50.0);
        QTRY_VERIFY_WITH_TIMEOUT(!flag("historyBusy"), 5000);
        QCOMPARE(history().size(), 2);
        QCOMPARE(history().first().toMap()["source"].toString(), QString("Pragus"));
    }
    void regenerateRedoesLastAnswerWithPreviousContext() {
        QVERIFY(send("Primeira"));
        QTRY_VERIFY_WITH_TIMEOUT(!flag("busy"), 10000);
        QVERIFY(send("Segunda"));
        QTRY_VERIFY_WITH_TIMEOUT(!flag("busy"), 10000);
        QCOMPARE(messages()->rowCount(), 4);
        // Regenerar a partir da resposta: pega a pergunta que veio antes dela.
        const QString answerId = messages()->data(messages()->index(3, 0), Qt::UserRole + 3).toString();
        QVERIFY(callBool("resend", answerId));
        QTRY_VERIFY_WITH_TIMEOUT(!flag("busy"), 10000);
        QCOMPARE(messages()->rowCount(), 4);
        QCOMPARE(allBodies(), QString("Primeira\nResposta: Primeira\nSegunda\nResposta: Segunda"));
        // O que veio antes segue como contexto de uma conversa nova; a pergunta refeita vai junto.
        const auto content = lastUserContent();
        QCOMPARE(content.size(), 2);
        QVERIFY(content[0].toObject()["text"].toString().contains("Primeira"));
        QVERIFY(!content[0].toObject()["text"].toString().contains("Segunda"));
        QCOMPARE(content[1].toObject()["text"].toString(), QString("Segunda"));
    }
    void editReplacesQuestionAndDropsLaterMessages() {
        QVERIFY(send("Original"));
        QTRY_VERIFY_WITH_TIMEOUT(!flag("busy"), 10000);
        QVERIFY(send("Depois"));
        QTRY_VERIFY_WITH_TIMEOUT(!flag("busy"), 10000);
        const QString firstId = messages()->data(messages()->index(0, 0), Qt::UserRole + 3).toString();
        bool accepted = false;
        QVERIFY(QMetaObject::invokeMethod(m_client.get(), "resend", Q_RETURN_ARG(bool, accepted), Q_ARG(QString, firstId), Q_ARG(QString, "  Editada  ")));
        QVERIFY(accepted);
        QTRY_VERIFY_WITH_TIMEOUT(!flag("busy"), 10000);
        QCOMPARE(allBodies(), QString("Editada\nResposta: Editada"));
        QCOMPARE(lastUserContent().size(), 1);   // nada antes: não há contexto a reenviar
    }
    void resendIsRefusedWhileBusyOrForUnknownMessage() {
        QVERIFY(!callBool("resend", "inexistente"));
        QVERIFY(send("algo demorado"));
        QTRY_VERIFY_WITH_TIMEOUT(flag("busy"), 10000);
        const QString id = messages()->data(messages()->index(0, 0), Qt::UserRole + 3).toString();
        QVERIFY(!callBool("resend", id));
        QVERIFY(invoke("stop"));
        QTRY_VERIFY_WITH_TIMEOUT(!flag("busy"), 10000);
    }
    void restartRecoversLastConversationAndQuota() {
        QVERIFY(send("Lembre de mim"));
        QTRY_VERIFY_WITH_TIMEOUT(!flag("busy"), 10000);
        const QString session = threadId();
        cleanup();
        startClient();
        QCOMPARE(threadId(), session);
        QVERIFY(allBodies().contains("Resposta: Lembre de mim"));
        QCOMPARE(m_client->property("weeklyUsed").toDouble(), 50.0);
        QVERIFY(invoke("newChat"));
        cleanup();
        startClient();
        QVERIFY(threadId().isEmpty());
        QCOMPARE(messages()->rowCount(), 0);
    }
    void stopInterruptsAnswer() {
        QVERIFY(send("algo demorado"));
        QTRY_VERIFY_WITH_TIMEOUT(allBodies().contains("Parcial"), 10000);
        QVERIFY(flag("busy"));
        QVERIFY(invoke("stop"));
        QTRY_VERIFY_WITH_TIMEOUT(!flag("busy"), 10000);
        QCOMPARE(text("status"), QString("Resposta interrompida"));
        QCOMPARE(text("error"), QString());
        bool interrupted = false;
        for (const auto &row : entries("stdin")) if (row["stdin"].toObject()["request"].toObject()["subtype"] == "interrupt") interrupted = true;
        QVERIFY(interrupted);
    }
    void failedTurnShowsError() {
        QVERIFY(send("por favor falhe"));
        QTRY_VERIFY_WITH_TIMEOUT(!flag("busy"), 10000);
        QVERIFY(text("error").contains("Falha simulada"));
    }
    void importedHistoryIsSentAsContextOnce() {
        const QString path = m_data.path() + "/historico.json";
        QFile file(path); QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(R"({"messages":[{"role":"user","content":"Antes"},{"role":"assistant","content":"Depois"}]})"); file.close();
        QVERIFY(callBool("importConversation", QUrl::fromLocalFile(path)));
        QVERIFY(send("Continue"));
        QTRY_VERIFY_WITH_TIMEOUT(!flag("busy"), 10000);
        auto content = lastUserContent();
        QCOMPARE(content.size(), 2);
        QVERIFY(content[0].toObject()["text"].toString().contains("pragus-imported-history"));
        QVERIFY(send("De novo"));
        QTRY_VERIFY_WITH_TIMEOUT(!flag("busy"), 10000);
        content = lastUserContent();
        QCOMPARE(content.size(), 1);
        // Ao retomar, o contexto importado volta como mensagens e não como texto bruto.
        const QString session = threadId();
        QVERIFY(invoke("newChat"));
        QVERIFY(load(session));
        QVERIFY(allBodies().startsWith("Antes\nDepois\nContinue"));
    }
    void imageAndFileAttachmentsAreSent() {
        const QString image = m_data.path() + "/foto.png";
        QImage pixels(8, 8, QImage::Format_RGB32); pixels.fill(Qt::red); QVERIFY(pixels.save(image));
        const QString notes = m_data.path() + "/notas.txt";
        QFile file(notes); QVERIFY(file.open(QIODevice::WriteOnly)); file.write("conteudo do anexo"); file.close();
        QVERIFY(callBool("addAttachment", QUrl::fromLocalFile(image)));
        QVERIFY(callBool("addAttachment", QUrl::fromLocalFile(notes)));
        QVERIFY(send("Veja"));
        QTRY_VERIFY_WITH_TIMEOUT(!flag("busy"), 10000);
        const auto content = lastUserContent();
        QCOMPARE(content.size(), 3);
        const auto source = content[1].toObject()["source"].toObject();
        QCOMPARE(content[1].toObject()["type"].toString(), QString("image"));
        QCOMPARE(source["media_type"].toString(), QString("image/png"));
        QVERIFY(!QByteArray::fromBase64(source["data"].toString().toLatin1()).isEmpty());
        QVERIFY(content[2].toObject()["text"].toString().contains("conteudo do anexo"));
        QVERIFY(turnArgs().last()["argv"].toArray().contains("--add-dir"));
        // No histórico, anexos aparecem como rótulos, sem o texto interno do contexto.
        const QString session = threadId();
        QVERIFY(invoke("newChat"));
        QVERIFY(load(session));
        QVERIFY(!allBodies().contains("conteudo do anexo"));
        const auto files = messages()->data(messages()->index(0, 0), Qt::UserRole + 4).toList();
        QCOMPARE(files.size(), 2);
    }
    void modelWithoutEffortOmitsFlag() {
        QVERIFY(send("/model haiku"));
        QCOMPARE(text("model"), QString("haiku"));
        QVERIFY(m_client->property("efforts").toStringList().isEmpty());
        QVERIFY(send("Oi"));
        QTRY_VERIFY_WITH_TIMEOUT(!flag("busy"), 10000);
        QVERIFY(!turnArgs().last()["argv"].toArray().contains("--effort"));
    }
    void switchBetweenClaudeAndAntigravityKeepsContextAndUpdatesQuota() {
        // Começa no Claude, faz uma pergunta e alterna para o Antigravity mantendo a conversa na tela.
        QCOMPARE(text("provider"), QString("claude"));
        QCOMPARE(text("providerName"), QString("Claude"));
        QVERIFY(send("Meu projeto é o Plasdria"));
        QTRY_VERIFY_WITH_TIMEOUT(!flag("busy"), 10000);
        QCOMPARE(messages()->rowCount(), 2);
        QCOMPARE(messages()->data(messages()->index(1, 0), Qt::UserRole + 5).toString(), QString("Claude"));

        // Alterna para o Antigravity via propriedade ou comando /ia
        m_client->setProperty("provider", QString("antigravity"));
        QTRY_VERIFY_WITH_TIMEOUT(flag("ready"), 10000);
        QTRY_VERIFY_WITH_TIMEOUT(!flag("historyBusy"), 5000);
        QCOMPARE(text("provider"), QString("antigravity"));
        QCOMPARE(text("providerName"), QString("Antigravity"));
        QCOMPARE(text("model"), QString("gemini-4-argon"));
        QCOMPARE(m_client->property("efforts").toStringList(), QStringList({"low", "medium", "high"}));
        // Cota do grupo Gemini 4 Argon (85% livre -> 15% usado em 5h, 75% livre -> 25% usado na semana)
        QTRY_COMPARE_WITH_TIMEOUT(m_client->property("fiveHourUsed").toDouble(), 15.0, 10000);
        QCOMPARE(m_client->property("weeklyUsed").toDouble(), 25.0);

        // Mudar para modelo Claude no Antigravity atualiza a cota para o grupo Claude & GPT (60% livre -> 40% usado)
        m_client->setProperty("model", QString("claude-sonnet-5-5"));
        QCOMPARE(m_client->property("fiveHourUsed").toDouble(), 40.0);
        QCOMPARE(m_client->property("weeklyUsed").toDouble(), 50.0);
        m_client->setProperty("model", QString("gemini-4-argon"));

        // A conversa anterior do Claude continua visível e é enviada como contexto ao continuar no Antigravity
        QCOMPARE(messages()->rowCount(), 2);
        QVERIFY(send("Continue com você"));
        QTRY_VERIFY_WITH_TIMEOUT(!flag("busy"), 10000);
        QCOMPARE(messages()->rowCount(), 4);
        QVERIFY(allBodies().endsWith("Antigravity: Continue com você"));
        QCOMPARE(messages()->data(messages()->index(3, 0), Qt::UserRole + 5).toString(), QString("Antigravity"));

        // Verifica que o histórico da conversa anterior foi enviado no stdin do agy
        QJsonArray agyContent;
        for (const auto &row : entries("agy_stdin")) {
            const auto msg = row["agy_stdin"].toObject();
            if (msg["event"] == "user") agyContent = msg["message"].toObject()["content"].toArray();
        }
        bool hadImportedContext = false;
        for (const auto &item : agyContent) {
            if (item.toObject()["text"].toString().contains("pragus-imported-history")) hadImportedContext = true;
        }
        QVERIFY(hadImportedContext);
    }
};

int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    ChatClientTest test;
    return QTest::qExec(&test, argc, argv);
}
#include "chatclient_test.moc"
