#pragma once

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QObject>
#include <QTimer>
#include <QProcess>
#include <QVariantList>
#include <QJsonObject>

class DashboardClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString greeting READ greeting NOTIFY clockChanged)
    Q_PROPERTY(QString localDate READ localDate NOTIFY clockChanged)
    Q_PROPERTY(QString localTime READ localTime NOTIFY clockChanged)
    Q_PROPERTY(QString weatherLocation READ weatherLocation NOTIFY weatherChanged)
    Q_PROPERTY(bool weatherStale MEMBER m_weatherStale NOTIFY weatherChanged)
    Q_PROPERTY(QString weatherStatus READ weatherStatus NOTIFY weatherChanged)
    Q_PROPERTY(QString weatherSummary READ weatherSummary NOTIFY weatherChanged)
    Q_PROPERTY(QString weatherTemperature READ weatherTemperature NOTIFY weatherChanged)
    Q_PROPERTY(QStringList usbDevices READ usbDevices NOTIFY changed)
    Q_PROPERTY(QVariantList forecast READ forecast NOTIFY weatherChanged)
    // Detalhes do tempo agora: feelsLike, humidity, wind, windDirection, rainChance, uv, sunrise, sunset, isDay, code, high, low.
    Q_PROPERTY(QVariantMap weatherDetails MEMBER m_weatherDetails NOTIFY weatherChanged)
    // Próximas 12 horas: [{hour, temp, code, rain}].
    Q_PROPERTY(QVariantList hourly MEMBER m_hourly NOTIFY weatherChanged)
    // cpuModel, cores, cpuTemp, diskTemp, uptime, load, processes, swapUsedGiB, swapTotalGiB, distro, kernel, batteryState, batteryTime.
    Q_PROPERTY(QVariantMap systemDetails MEMBER m_systemDetails NOTIFY changed)
    Q_PROPERTY(QVariantList news READ news NOTIFY newsChanged)
    Q_PROPERTY(bool newsBusy MEMBER m_newsBusy NOTIFY newsChanged)
    Q_PROPERTY(QString newsStatus READ newsStatus NOTIFY newsChanged)
    Q_PROPERTY(double cpuUsage READ cpuUsage NOTIFY changed)
    Q_PROPERTY(double memoryUsedGiB MEMBER m_memoryUsedGiB NOTIFY changed)
    Q_PROPERTY(double memoryTotalGiB MEMBER m_memoryTotalGiB NOTIFY changed)
    Q_PROPERTY(double storageUsedGiB MEMBER m_storageUsedGiB NOTIFY changed)
    Q_PROPERTY(double storageTotalGiB MEMBER m_storageTotalGiB NOTIFY changed)
    Q_PROPERTY(QVariantList peripheralDevices READ peripheralDevices NOTIFY changed)
    Q_PROPERTY(double memoryUsage READ memoryUsage NOTIFY changed)
    Q_PROPERTY(double gpuUsage READ gpuUsage NOTIFY changed)
    Q_PROPERTY(double storageUsage READ storageUsage NOTIFY changed)
    Q_PROPERTY(double batteryPercent READ batteryPercent NOTIFY changed)
    Q_PROPERTY(QString batteryStatus READ batteryStatus NOTIFY changed)
    Q_PROPERTY(QString networkStatus READ networkStatus NOTIFY changed)
    Q_PROPERTY(QString metricsStatus READ metricsStatus NOTIFY changed)
    Q_PROPERTY(QString lastUpdated READ lastUpdated NOTIFY changed)
public:
    explicit DashboardClient(QObject *parent = nullptr);

    QString greeting() const { return m_greeting; }
    QString localDate() const { return m_date; }
    QString localTime() const { return m_time; }
    QString weatherLocation() const { return m_weatherLocation; }
    QString weatherStatus() const { return m_weatherStatus; }
    QString weatherSummary() const { return m_weatherSummary; }
    QString weatherTemperature() const { return m_weatherTemperature; }
    QStringList usbDevices() const { return m_usbDevices; }
    QVariantList forecast() const { return m_forecast; }
    QVariantList news() const { return m_news; }
    QString newsStatus() const { return m_newsStatus; }
    double cpuUsage() const { return m_cpuUsage; }
    double memoryUsage() const { return m_memoryUsage; }
    double gpuUsage() const { return m_gpuUsage; }
    double storageUsage() const { return m_storageUsage; }
    double batteryPercent() const { return m_batteryPercent; }
    QString batteryStatus() const { return m_batteryStatus; }
    QString networkStatus() const { return m_networkStatus; }
    QString metricsStatus() const { return m_metricsStatus; }
    QString lastUpdated() const { return m_lastUpdated; }

    QVariantList peripheralDevices() const;
    Q_INVOKABLE void start();
    Q_INVOKABLE void refresh();
    // Cidade vazia volta à detecção automática pela rede.
    Q_INVOKABLE void setLocation(const QString &city, double latitude, double longitude);
    // Tópico do Google News: "" (principais), TECHNOLOGY, SPORTS, BUSINESS, ENTERTAINMENT, SCIENCE, HEALTH.
    Q_INVOKABLE void setNewsTopic(const QString &topic);
    // Notificação do sistema (D-Bus org.freedesktop.Notifications), usada pelos alarmes dos lembretes.
    Q_INVOKABLE void notify(const QString &title, const QString &body);
    // Igual a notify, com botões. `actions` vem em pares id, rótulo (["open", "Abrir", "mute", "Silenciar"]);
    // ao clicar, sai o sinal notificationAction(tag, id). Sem servidor de notificações que aceite botões, só aparece o aviso.
    Q_INVOKABLE void notifyAction(const QString &title, const QString &body, const QString &tag, const QStringList &actions);

signals:
    void notificationAction(const QString &tag, const QString &action);
    void clockChanged();
    void weatherChanged();
    void newsChanged();
    void changed();

private slots:
    void onActionInvoked(uint id, const QString &action);
    void onNotificationClosed(uint id, uint reason);

private:
    QHash<uint, QString> m_notificationTags;
    void requestBatteries();
    void updateClock();
    void updateMetrics();
    void updateSystemDetails();
    void requestBatteryDetails();
    void requestWeather();
    void requestLocation();
    void requestLocationProvider(int provider);
    void loadWeatherCache();
    bool applyFixedLocation();
    void saveWeatherCache();
    void requestNews();
    void parseWeather(const QByteArray &data, bool fromCache = false);
    void parseNews(const QByteArray &data);
    void failWeather(const QString &message);
    void failNews(const QString &message);
    QNetworkReply *get(const QUrl &url);

    QNetworkAccessManager m_network;
    QTimer m_batteryTimer;
    QVariantList m_upowerDevices, m_bluetoothDevices;
    double m_memoryUsedGiB = -1, m_memoryTotalGiB = -1;
    double m_storageUsedGiB = -1, m_storageTotalGiB = -1;
    QTimer m_clockTimer;
    QTimer m_metricsTimer;
    QTimer m_weatherTimer;
    QTimer m_weatherRetry;
    bool m_locationBusy = false, m_weatherBusy = false, m_weatherStale = false;
    qint64 m_locationUpdatedAt = 0, m_weatherUpdatedAt = 0;
    QJsonObject m_lastWeatherData;
    QTimer m_newsTimer;
    QProcess m_gpuProcess;
    QString m_greeting;
    QString m_date;
    QString m_time;
    QString m_weatherLocation = QStringLiteral("Localizando…");
    QString m_weatherLatitude = QString();
    QString m_weatherLongitude = QString();
    QString m_weatherStatus = QStringLiteral("Carregando clima real");
    QString m_weatherSummary;
    QString m_weatherTemperature;
    QVariantList m_forecast;
    QVariantMap m_weatherDetails, m_systemDetails;
    QVariantList m_hourly;
    QVariantList m_news;
    bool m_newsBusy = false;
    QString m_newsStatus = QStringLiteral("Carregando notícias reais");
    double m_cpuUsage = -1;
    double m_memoryUsage = -1;
    double m_gpuUsage = -1;
    double m_storageUsage = -1;
    double m_batteryPercent = -1;
    QString m_batteryStatus = QStringLiteral("Indisponível");
    QStringList m_usbDevices;
    QString m_networkStatus = QStringLiteral("Indisponível");
    QString m_metricsStatus = QStringLiteral("Carregando métricas");
    QString m_lastUpdated;
    quint64 m_cpuTotal = 0;
    quint64 m_cpuIdle = 0;
    bool m_started = false;
    QString m_fixedCity, m_newsTopic;
    double m_fixedLatitude = 0, m_fixedLongitude = 0;
};
