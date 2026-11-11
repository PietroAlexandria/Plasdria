#pragma once

#include <QObject>
#include <QString>

// Cofre de senhas do sistema (Secret Service: KWallet/ksecretd, GNOME Keyring…).
// Guarda a chave da API e o link da agenda fora do arquivo de configuração do Plasma,
// que qualquer usuário do computador consegue ler. Chamadas bloqueiam por pouco tempo.
class SecretClient : public QObject {
    Q_OBJECT
public:
    explicit SecretClient(QObject *parent = nullptr);

    // true se o serviço existe e a coleção padrão está desbloqueada.
    Q_INVOKABLE bool available();
    // Texto guardado para a chave, ou "" (não existe, bloqueado ou sem serviço).
    Q_INVOKABLE QString read(const QString &key);
    // Guarda (ou, com valor vazio, apaga). Devolve false se não conseguiu.
    Q_INVOKABLE bool write(const QString &key, const QString &value);
};
