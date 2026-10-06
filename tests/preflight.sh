#!/usr/bin/env bash
# Pre-push preflight: run the same gates the Omarchy plugin marketplace runs,
# locally, against the current commit — no push and no network required.
#
#   1. Manifest / Quattro compatibility  -> omarchy plugin validate
#   2. QML checks                        -> Qt6 qmllint (via test_panel.sh)
#   3. Full test suite                   -> tests/run_tests.sh
#   4. Automated Security Baseline       -> tests/marketplace-baseline-local.mjs
#
# Install as a git hook with:
#   git config core.hooksPath .githooks
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

step() { printf '\n\033[0;34m▶ %s\033[0m\n' "$*"; }
ok()   { printf '\033[0;32m✅ %s\033[0m\n' "$*"; }
warn() { printf '\033[0;33m⚠️  %s\033[0m\n' "$*"; }
fail() { printf '\033[0;31m❌ %s\033[0m\n' "$*" >&2; exit 1; }

step "1/4 Manifest validation (Quattro)"
if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  omarchy-plugin-validate "$root"
elif command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$root"
else
  warn "omarchy CLI not found; falling back to schema checks"
  bash "$root/tests/test_manifest.sh"
fi
ok "manifest validation passed"

step "2/4 QML checks"
bash "$root/tests/test_panel.sh"
ok "QML checks passed"

step "3/4 Test suite"
bash "$root/tests/run_tests.sh"
ok "test suite passed"

step "4/4 Automated security baseline (local commit)"
git -C "$root" rev-parse HEAD >/dev/null 2>&1 \
  || fail "no git commit found; commit your changes first (the baseline scans HEAD)"
node "$root/tests/marketplace-baseline-local.mjs"
ok "security baseline passed"

printf '\n'
ok "Preflight complete — all checks passed."
