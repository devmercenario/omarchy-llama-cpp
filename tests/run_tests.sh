#!/usr/bin/env bash
# Master test runner for omarchy-llama-cpp.
set -uo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
total=0
failed=0

run() {
  local name="$1"; shift
  total=$((total + 1))
  printf '\n\033[0;34m▶ %s\033[0m\n' "$name"
  if "$@"; then
    printf '\033[0;32m✔ %s passed\033[0m\n' "$name"
  else
    printf '\033[0;31m✖ %s failed\033[0m\n' "$name" >&2
    failed=$((failed + 1))
  fi
}

run "Manifest"   bash "$dir/test_manifest.sh"
run "QML"        bash "$dir/test_panel.sh"
run "Helper"     bash "$dir/test_helper.sh"

printf '\n'
if (( failed == 0 )); then
  printf '\033[0;32mAll %d suites passed\033[0m\n' "$total"
  exit 0
fi
printf '\033[0;31m%d/%d suites failed\033[0m\n' "$failed" "$total" >&2
exit 1
