import QtQuick
import QtQuick.Layouts

// Selo da IA escolhida (Antigravity, Claude, Codex, Gemini, Ollama ou API compatível).
Image {
    id: icon
    property string provider: ""
    property int size: 20
    readonly property var known: ["antigravity", "claude", "codex", "gemini", "ollama", "custom"]
    readonly property string key: known.indexOf(provider) >= 0 ? provider : "custom"
    source: "assets/provider-" + key + ".svg"
    width: size; height: size
    Layout.preferredWidth: size; Layout.preferredHeight: size
    sourceSize: Qt.size(size * 3, size * 3)
    fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true
}
