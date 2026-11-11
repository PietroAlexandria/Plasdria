#!/usr/bin/env bash
set -euo pipefail
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_qmake="$(command -v qmake6 || command -v qmake || true)"
if [[ -z "$task_qmake" && -x /usr/lib/qt6/bin/qmake ]]; then task_qmake=/usr/lib/qt6/bin/qmake; fi
if [[ -z "$task_qmake" ]]; then echo 'Instale o qmake do Qt 6.' >&2; exit 1; fi
task_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/pragus-tests.XXXXXX")"
trap 'rm -rf "$task_test_dir"' EXIT
"$task_root/build.sh"
# Leitor de prazos e de agendas iCalendar (QML puro, sem rede).
TZ=America/Sao_Paulo QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 QT_MESSAGE_PATTERN="%{message}" \
    qml6 "$task_root/tests/timeparse_test.qml" 2>&1 | grep -E "FALHOU|PASSARAM|FALHA" | tee "$task_test_dir/timeparse.out"
grep -q PASSARAM "$task_test_dir/timeparse.out"
# Edição do layout com mouse simulado e agenda iCal baixada de um servidor local (que se encerra sozinho).
(timeout 120 python3 -m http.server 18765 --bind 127.0.0.1 --directory "$task_root/tests/data" >/dev/null 2>&1 &)
sleep 0.8
for task_qml in tst_shell_edit tst_icsfeed tst_cards; do
    QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input "$task_root/tests/$task_qml.qml" 2>&1 \
        | tee "$task_test_dir/$task_qml.out" | grep -E "^(FAIL|PASS|Totals)|Loc:|Actual|Expected"
    grep -q " 0 failed" "$task_test_dir/$task_qml.out"
done
for task_suite in chathistory chatclient_test mediaclient_test; do
    mkdir "$task_test_dir/$task_suite"
    cd "$task_test_dir/$task_suite"
    "$task_qmake" "$task_root/tests/$task_suite.pro"
    make -j2
    if [[ "$task_suite" == chathistory ]]; then
        ./chathistory_test
    elif [[ "$task_suite" == mediaclient_test ]]; then
        dbus-run-session -- ./mediaclient_test
    else
        QT_QPA_PLATFORM=offscreen ./chatclient_test
    fi
done
