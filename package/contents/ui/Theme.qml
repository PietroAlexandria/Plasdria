import QtQuick

// Paleta e medidas compartilhadas por todos os cartões.
QtObject {
    // Cor de destaque escolhida; no tema claro ela escurece um pouco para o texto continuar legível.
    property color accentBase: "#3daee9"
    property real backgroundOpacity: 0.94
    property bool animations: true
    // "dark" | "light" | "system" (system segue o tema do Plasma, informado em systemDark).
    property string mode: "dark"
    property bool systemDark: true
    readonly property bool dark: mode === "light" ? false : mode === "system" ? systemDark : true

    readonly property color accent: dark ? accentBase : Qt.darker(accentBase, 1.3)
    readonly property color background: dark ? Qt.rgba(0.075, 0.08, 0.105, backgroundOpacity) : Qt.rgba(0.955, 0.96, 0.972, backgroundOpacity)
    readonly property color card: dark ? "#1b1d27" : "#ffffff"
    readonly property color cardRaised: dark ? "#232634" : "#eaedf4"
    readonly property color border: dark ? "#2c2f3d" : "#d6dae5"
    readonly property color ink: dark ? "#eceef5" : "#1b1d27"
    readonly property color muted: dark ? "#9ba1b5" : "#555b70"
    readonly property color faint: dark ? "#646a80" : "#8389a0"
    readonly property color good: dark ? "#5fd38a" : "#1b8a4c"
    readonly property color warn: dark ? "#f2b64c" : "#a86b00"
    readonly property color bad: dark ? "#ff6b6b" : "#d03a3a"
    // Véu sutil sobre o cartão (peças em destaque) e texto sobre cor de destaque cheia.
    readonly property color tint: dark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(0, 0, 0, 0.04)
    readonly property color textOnAccent: "#101119"
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, dark ? 0.16 : 0.12)
    readonly property color accentLine: Qt.rgba(accent.r, accent.g, accent.b, 0.45)

    readonly property int radius: 14
    readonly property int gap: 10
    readonly property int pad: 12
    readonly property int duration: animations ? 180 : 0

    // Uso: verde até 70%, âmbar até 90%, vermelho acima.
    function usageColor(used) { return used < 0 ? faint : used < 70 ? good : used < 90 ? warn : bad }
    // Carga restante (bateria, cota): vermelho até 20%, âmbar até 40%.
    function levelColor(left) { return left < 0 ? faint : left <= 20 ? bad : left <= 40 ? warn : good }
}
