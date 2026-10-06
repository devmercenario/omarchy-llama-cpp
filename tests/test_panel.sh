#!/usr/bin/env bash
# QML checks for the bar widget and its dropdown panel: syntax via Qt6
# qmllint when available, plus structural assertions.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

fail() { echo "FAIL: $*" >&2; exit 1; }

for qml in BarWidget.qml Panel.qml; do
  [[ -f $qml ]] || fail "missing $qml"
done

# Prefer a Qt6 qmllint: the Qt5 build commonly on PATH cannot parse Quickshell
# QML and exits non-zero without a useful message.
lint=""
for cand in /usr/lib/qt6/bin/qmllint "$(command -v qmllint 2>/dev/null || true)"; do
  [[ -n $cand && -x $cand ]] || continue
  if "$cand" --version 2>/dev/null | grep -qE '^qmllint 6'; then lint="$cand"; break; fi
done

if [[ -n $lint ]]; then
  for qml in BarWidget.qml Panel.qml; do
    if ! "$lint" "$qml" >/tmp/omarchy-llama-qmllint.out 2>&1; then
      cat /tmp/omarchy-llama-qmllint.out >&2
      fail "qmllint reported errors in $qml"
    fi
  done
  echo "qmllint 6 OK"
else
  echo "note: no Qt6 qmllint found; skipped syntax check"
fi

grep -q 'moduleName: "devmercenario.llama-cpp"' BarWidget.qml || fail "BarWidget moduleName mismatch"
grep -q 'IpcHandler' BarWidget.qml || fail "no IpcHandler for shell IPC"
grep -q 'BarIconButton' BarWidget.qml || fail "no BarIconButton"
grep -q 'assets/llama.svg' BarWidget.qml || fail "bundled icon is not referenced"
grep -q 'statusProc' BarWidget.qml || fail "no status polling process"
grep -q 'panelLoader' BarWidget.qml || fail "no panel loader"

grep -q 'KeyboardPanel' Panel.qml || fail "panel does not use KeyboardPanel"
grep -q 'PanelKeyCatcher' Panel.qml || fail "panel does not use PanelKeyCatcher"
grep -q '"toggle", id' Panel.qml || fail "panel rows do not toggle a model"
grep -q 'ToggleSwitch' Panel.qml || fail "panel rows do not use an on/off switch"
grep -q 'Repeater' Panel.qml || fail "panel does not list models"

python3 - <<'PY'
import sys
for path in ("BarWidget.qml", "Panel.qml"):
    src = open(path, encoding="utf-8").read()
    for left, right in (("{", "}"), ("(", ")"), ("[", "]")):
        if src.count(left) != src.count(right):
            print(f"{path}: unbalanced {left}{right}: {src.count(left)} vs {src.count(right)}", file=sys.stderr)
            sys.exit(1)
PY

echo "qml OK"
