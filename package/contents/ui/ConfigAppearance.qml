import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page
    property string cfg_accentColor
    property alias cfg_backgroundOpacity: opacitySlider.value
    property alias cfg_animations: animations.checked
    property string cfg_themeMode
    property alias cfg_uiScale: scaleSlider.value
    property string cfg_density
    property alias cfg_iconScale: iconSlider.value

    readonly property var palette: [
        {color: "#3daee9", name: "Plasdria (azul)"}, {color: "#2bd9b0", name: "Plasdria (verde-água)"}, {color: "#8b7cff", name: "Violeta"},
        {color: "#5fd38a", name: "Verde"}, {color: "#f2b64c", name: "Âmbar"}, {color: "#ff7a6b", name: "Coral"},
        {color: "#ff6fb5", name: "Rosa"}, {color: "#c7cbd6", name: "Grafite"}
    ]

    Kirigami.FormLayout {
        RowLayout {
            Kirigami.FormData.label: "Tema:"
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: [{id: "dark", name: "Escuro"}, {id: "light", name: "Claro"}, {id: "system", name: "Do sistema"}]
                delegate: QQC2.RadioButton {
                    required property var modelData
                    text: modelData.name
                    checked: page.cfg_themeMode === modelData.id
                    onClicked: page.cfg_themeMode = modelData.id
                }
            }
        }
        RowLayout {
            Kirigami.FormData.label: "Tamanho geral:"
            spacing: Kirigami.Units.smallSpacing
            QQC2.Slider { id: scaleSlider; from: 50; to: 160; stepSize: 5; Layout.preferredWidth: Kirigami.Units.gridUnit * 12 }
            QQC2.Label { text: Math.round(scaleSlider.value) + "%"; Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5 }
            Repeater {
                model: [{v: 80, n: "Pequeno"}, {v: 100, n: "Normal"}, {v: 125, n: "Grande"}]
                delegate: QQC2.Button { required property var modelData; text: modelData.n; onClicked: scaleSlider.value = modelData.v }
            }
        }
        QQC2.Label {
            text: "Muda fontes, ícones e cartões juntos. Em tamanhos maiores o layout se reorganiza sozinho para caber."
            wrapMode: Text.Wrap; opacity: 0.7
            Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        }
        RowLayout {
            Kirigami.FormData.label: "Espaço nos cartões:"
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: [{id: "compact", name: "Compacto"}, {id: "normal", name: "Normal"}, {id: "comfortable", name: "Confortável"}]
                delegate: QQC2.RadioButton {
                    required property var modelData
                    text: modelData.name
                    checked: page.cfg_density === modelData.id
                    onClicked: page.cfg_density = modelData.id
                }
            }
        }
        RowLayout {
            Kirigami.FormData.label: "Tamanho dos ícones:"
            spacing: Kirigami.Units.smallSpacing
            QQC2.Slider { id: iconSlider; from: 60; to: 160; stepSize: 5; Layout.preferredWidth: Kirigami.Units.gridUnit * 12 }
            QQC2.Label { text: Math.round(iconSlider.value) + "%" }
        }
        RowLayout {
            Kirigami.FormData.label: "Cor de destaque:"
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: page.palette
                delegate: Rectangle {
                    required property var modelData
                    width: Kirigami.Units.gridUnit * 1.6; height: width; radius: width / 2
                    color: modelData.color
                    border.width: page.cfg_accentColor.toLowerCase() === modelData.color ? 3 : 0
                    border.color: Kirigami.Theme.textColor
                    QQC2.ToolTip.visible: hover.hovered; QQC2.ToolTip.text: modelData.name
                    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: page.cfg_accentColor = modelData.color }
                }
            }
        }
        RowLayout {
            Kirigami.FormData.label: "Opacidade do fundo:"
            QQC2.Slider { id: opacitySlider; from: 60; to: 100; stepSize: 1; Layout.preferredWidth: Kirigami.Units.gridUnit * 12 }
            QQC2.Label { text: Math.round(opacitySlider.value) + "%" }
        }
        QQC2.CheckBox { id: animations; Kirigami.FormData.label: "Movimento:"; text: "Animações (ícones do clima, transições)" }
    }
}
