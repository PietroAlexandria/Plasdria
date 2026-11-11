import QtQuick
import QtTest
import "../package/contents/ui"

// Tema escuro, claro e "do sistema".
Item {
    width: 100; height: 100
    Theme { id: theme }
    TestCase {
        name: "Tema"
        when: windowShown
        function lum(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
        function test_escuro_e_o_padrao() {
            theme.mode = "dark"; theme.systemDark = false
            verify(theme.dark)
            verify(lum(theme.ink) > lum(theme.card))
        }
        function test_claro_inverte_texto_e_fundo() {
            theme.mode = "light"; theme.systemDark = true
            verify(!theme.dark)
            verify(lum(theme.ink) < 0.3 && lum(theme.card) > 0.9)
            verify(lum(theme.muted) < lum(theme.card))
        }
        function test_sistema_segue_o_plasma() {
            theme.mode = "system"
            theme.systemDark = true;  verify(theme.dark)
            theme.systemDark = false; verify(!theme.dark)
            verify(lum(theme.card) > 0.9)
        }
        function test_valor_desconhecido_cai_no_escuro() {
            theme.mode = "qualquer"; verify(theme.dark)
        }
        function test_destaque_escurece_no_claro() {
            theme.accentBase = "#3daee9"
            theme.mode = "dark";  const a = lum(theme.accent)
            theme.mode = "light"; verify(lum(theme.accent) < a)
        }
    }
}
