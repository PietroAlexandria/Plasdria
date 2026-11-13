.pragma library
// Itens do cartão Ações rápidas, na ordem padrão. cfg.quickItems guarda os ids ligados, na ordem
// escolhida, como JSON; vazio (ou inválido) = todos, na ordem padrão.
var all = [
    {id: "dnd", kind: "toggle", text: "Não perturbe", icon: "notifications-disabled-symbolic"},
    {id: "night", kind: "toggle", text: "Luz noturna", icon: "redshift-status-on"},
    {id: "caffeine", kind: "toggle", text: "Manter acordado", icon: "system-suspend-inhibited"},
    {id: "wifi", kind: "toggle", text: "Wi-Fi", icon: "network-wireless-symbolic"},
    {id: "profile", kind: "profile", text: "Perfil de energia", icon: "battery-profile-balanced-symbolic"},
    {id: "lock", kind: "action", text: "Bloquear", icon: "system-lock-screen-symbolic"},
    {id: "suspend", kind: "action", text: "Suspender", icon: "system-suspend-symbolic"},
    {id: "shot", kind: "action", text: "Captura", icon: "camera-photo-symbolic"},
    {id: "session", kind: "action", text: "Desligar…", icon: "system-shutdown-symbolic"}
];

function ids() { return all.map(function (x) { return x.id }) }

// Lista de ids ligados, na ordem escolhida.
function enabled(text) {
    var list = null
    try { list = JSON.parse(text || "") } catch (e) {}
    if (!Array.isArray(list)) return ids()
    var known = ids(), seen = {}
    return list.filter(function (id) { return known.indexOf(id) >= 0 && !seen[id] && (seen[id] = true) })
}

function info(id) { for (var i = 0; i < all.length; ++i) if (all[i].id === id) return all[i]; return null }

// Liga/desliga um item: um item religado volta no fim da lista.
function toggled(text, id) {
    var list = enabled(text), i = list.indexOf(id)
    if (i >= 0) list.splice(i, 1); else list.push(id)
    return JSON.stringify(list)
}

// Move um item ligado uma posição para cima (-1) ou para baixo (+1).
function moved(text, id, delta) {
    var list = enabled(text), i = list.indexOf(id), j = i + delta
    if (i < 0 || j < 0 || j >= list.length) return JSON.stringify(list)
    list[i] = list[j]; list[j] = id
    return JSON.stringify(list)
}
