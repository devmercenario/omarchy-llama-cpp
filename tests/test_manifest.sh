#!/usr/bin/env bash
# Manifest checks for the Omarchy plugin contract, plus `omarchy plugin
# validate` when the CLI is available (the same gate the marketplace runs).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f manifest.json ]] || fail "manifest.json is missing"
jq -e . manifest.json >/dev/null 2>&1 || fail "manifest.json is not valid JSON"

[[ "$(jq -r '.schemaVersion' manifest.json)" == "1" ]] || fail "schemaVersion must be the number 1"

id="$(jq -r '.id // ""' manifest.json)"
[[ -n $id ]] || fail "id is empty"
[[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "invalid id: $id"
[[ $id != omarchy.* ]] || fail "id uses the reserved omarchy.* namespace"
[[ $id != *".."* ]] || fail "id contains '..'"

for field in id name version author description kinds entryPoints; do
  jq -e --arg f "$field" 'has($f)' manifest.json >/dev/null || fail "missing required field: $field"
done

jq -e '(.kinds | type) == "array" and (.kinds | length) > 0' manifest.json >/dev/null \
  || fail "kinds must be a non-empty array"
jq -e '(.entryPoints | type) == "object"' manifest.json >/dev/null \
  || fail "entryPoints must be an object"

entry="$(jq -r '.entryPoints.barWidget // ""' manifest.json)"
[[ -n $entry ]] || fail "kinds includes bar-widget but entryPoints.barWidget is missing"
[[ $entry != /* && $entry != *".."* ]] || fail "entryPoints.barWidget must be a safe relative path"
[[ -f $entry ]] || fail "entry point file not found: $entry"

section="$(jq -r '.barWidget.defaultSection // ""' manifest.json)"
[[ -z $section || $section =~ ^(left|center|right)$ ]] || fail "barWidget.defaultSection must be left, center, or right"

link="$(find . -name .git -prune -o -type l -print -quit)"
[[ -z $link ]] || fail "symlinks are not allowed in a plugin folder: $link"

if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  omarchy-plugin-validate "$root" >/dev/null || fail "omarchy plugin validate rejected the folder"
elif command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$root" >/dev/null || fail "omarchy plugin validate rejected the folder"
else
  echo "note: omarchy CLI not found; ran schema checks only"
fi

echo "manifest OK ($id)"
