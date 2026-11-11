import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Rodapé do clima: detalhes de hoje, próximas horas e a semana.
// compact: empilha as três partes (layouts médio e estreito).
Rectangle {
    id: footer
    required property var t
    required property var dash
    property bool compact: false
    readonly property var w: dash.weatherDetails || ({})

    radius: t.radius
    color: t.card
    border.color: t.border
    implicitHeight: layout.implicitHeight + 20

    function deg(v) { return v > -999 ? v + "°" : "—" }
    function uvLabel(uv) { return uv < 0 ? "" : uv <= 2 ? "baixo" : uv <= 5 ? "moderado" : uv <= 7 ? "alto" : uv <= 10 ? "muito alto" : "extremo" }

    component Heading: Text { color: footer.t.muted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 0.8 }

    GridLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 10
        anchors.leftMargin: 14; anchors.rightMargin: 14
        columns: footer.compact ? 1 : 5
        columnSpacing: 16; rowSpacing: 10

        // Hoje em detalhes
        ColumnLayout {
            spacing: 4
            Layout.preferredWidth: footer.compact ? -1 : 300
            Layout.alignment: Qt.AlignTop
            Heading { text: "HOJE EM " + (footer.dash.weatherLocation || "").toUpperCase() }
            GridLayout {
                columns: 2; columnSpacing: 14; rowSpacing: 2
                Repeater {
                    model: [
                        ["Sensação", footer.deg(footer.w.feelsLike)],
                        ["Umidade", footer.w.humidity >= 0 ? footer.w.humidity + "%" : "—"],
                        ["Vento", footer.w.wind >= 0 ? footer.w.wind + " km/h " + (footer.w.windDirection || "") : "—"],
                        ["Chuva", footer.w.rainChance >= 0 ? footer.w.rainChance + "%" : "—"],
                        ["UV", footer.w.uv >= 0 ? footer.w.uv + " · " + footer.uvLabel(footer.w.uv) : "—"],
                        ["Sol", footer.w.sunrise ? footer.w.sunrise + " – " + footer.w.sunset : "—"]
                    ]
                    delegate: RowLayout {
                        required property var modelData
                        spacing: 6
                        Text { text: modelData[0]; color: footer.t.faint; font.pixelSize: 11; Layout.preferredWidth: 58 }
                        Text { text: modelData[1]; color: footer.t.ink; font.pixelSize: 11 }
                    }
                }
            }
        }

        Rectangle { visible: !footer.compact; Layout.fillHeight: true; width: 1; color: footer.t.border }

        // Próximas horas
        ColumnLayout {
            spacing: 4
            Layout.fillWidth: true; Layout.preferredWidth: 2
            Layout.alignment: Qt.AlignTop
            Heading { text: "PRÓXIMAS HORAS" }
            RowLayout {
                Layout.fillWidth: true; spacing: 0
                Repeater {
                    model: footer.dash.hourly.slice(0, footer.compact ? 6 : 8)
                    delegate: Item {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitWidth: hourCol.implicitWidth; implicitHeight: hourCol.implicitHeight
                        ColumnLayout {
                            id: hourCol; anchors.horizontalCenter: parent.horizontalCenter; spacing: 0
                            Text { text: modelData.now ? "Agora" : modelData.hour; color: modelData.now ? footer.t.accent : footer.t.muted; font.pixelSize: 10; Layout.alignment: Qt.AlignHCenter }
                            Item { Layout.preferredWidth: 22; Layout.preferredHeight: 20; Layout.alignment: Qt.AlignHCenter
                                WeatherIcon { t: footer.t; anchors.centerIn: parent; code: modelData.code; animated: false; scale: 0.48 } }
                            Text { text: modelData.temp + "°" + (modelData.rain > 20 ? " · " + modelData.rain + "%" : ""); color: footer.t.ink; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }
                        }
                    }
                }
            }
        }

        Rectangle { visible: !footer.compact; Layout.fillHeight: true; width: 1; color: footer.t.border }

        // Semana
        ColumnLayout {
            spacing: 4
            Layout.fillWidth: true; Layout.preferredWidth: 3
            Layout.alignment: Qt.AlignTop
            Heading { text: "SEMANA" }
            RowLayout {
                Layout.fillWidth: true; spacing: 0
                Repeater {
                    model: footer.compact ? footer.dash.forecast.slice(0, 5) : footer.dash.forecast
                    delegate: Item {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitWidth: dayCol.implicitWidth; implicitHeight: dayCol.implicitHeight
                        ColumnLayout {
                            id: dayCol; anchors.horizontalCenter: parent.horizontalCenter; spacing: 0
                            Text { text: modelData.isToday ? "Hoje" : modelData.day.slice(0, 3); color: modelData.isToday ? footer.t.accent : footer.t.muted; font.pixelSize: 10; Layout.alignment: Qt.AlignHCenter }
                            Item { Layout.preferredWidth: 22; Layout.preferredHeight: 20; Layout.alignment: Qt.AlignHCenter
                                WeatherIcon { t: footer.t; anchors.centerIn: parent; code: modelData.code; animated: false; scale: 0.48 } }
                            Text { text: modelData.high + " " + modelData.low; color: footer.t.ink; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }
                            Text { text: modelData.rain > 0 ? "☂ " + modelData.rain + "%" : " "; color: footer.t.rainText; font.pixelSize: 9; Layout.alignment: Qt.AlignHCenter }
                        }
                    }
                }
            }
        }
    }
}
