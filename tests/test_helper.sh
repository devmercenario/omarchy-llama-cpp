#!/usr/bin/env bash
# Helper tests against a faithful `llama serve` test double, so no real model
# is ever launched and no network is used.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$root/bin/omarchy-llama-cpp"
[[ -x $helper ]] || { echo "FAIL: $helper is not executable" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "note: python3 missing; skipping helper tests"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "note: jq missing; skipping helper tests"; exit 0; }

tmp="$(mktemp -d)"
port_a=$(( 40000 + RANDOM % 10000 ))
port_b=$(( port_a + 1 ))
export OMARCHY_LLAMA_CONFIG="$tmp/models.json"

cleanup() {
  "$helper" stop >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

cat > "$tmp/llama" <<'EOF'
#!/usr/bin/env bash
port=9999; host=127.0.0.1
while (( $# > 0 )); do
  case "$1" in
    --port) port="${2:-}"; shift 2;;
    --host) host="${2:-}"; shift 2;;
    *) shift;;
  esac
done
PORT="$port" HOST="$host" exec -a llama python3 -c '
import http.server, os, socketserver
host = os.environ.get("HOST", "127.0.0.1")
port = int(os.environ.get("PORT", "8080"))
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer((host, port), http.server.SimpleHTTPRequestHandler) as s:
    s.serve_forever()
' serve --port "$port"
EOF
chmod +x "$tmp/llama"

jq -n --arg bin "$tmp/llama" --argjson pa "$port_a" --argjson pb "$port_b" '{
  models: [
    { id: "alpha", name: "Alpha", host: "127.0.0.1", port: $pa,
      command: [$bin, "serve", "--port", ($pa|tostring)] },
    { id: "bravo", name: "Bravo", host: "127.0.0.1", port: $pb,
      command: [$bin, "serve", "--port", ($pb|tostring)] }
  ]
}' > "$tmp/models.json"

h() { "$helper" "$@"; }

wait_port() {
  local port=$1 i
  for i in $(seq 1 80); do
    (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && { exec 3>&- 3<&-; return 0; }
    sleep 0.1
  done
  return 1
}

# Registry listing.
json="$(h list --json)"
echo "$json" | jq -e . >/dev/null || fail "list --json is not valid JSON: $json"
[[ "$(echo "$json" | jq -r '.configSource')" == "user" ]] || fail "configSource should be user"
[[ "$(echo "$json" | jq -r '.models | length')" == "2" ]] || fail "expected 2 models: $json"
[[ "$(echo "$json" | jq -r '.state')" == "stopped" ]] || fail "expected stopped: $json"

# Nothing running yet.
json="$(h status --json)"
[[ "$(echo "$json" | jq -r '.state')" == "stopped" ]] || fail "expected stopped status: $json"
if h status >/dev/null 2>&1; then fail "status must exit non-zero while stopped"; fi

# Unknown model is refused.
if h start nope >/dev/null 2>&1; then fail "start should fail for an unknown id"; fi

# Start alpha.
h start alpha >/dev/null || fail "start alpha failed"
wait_port "$port_a" || fail "alpha never listened on $port_a"
json="$(h status --json)"
[[ "$(echo "$json" | jq -r '.state')" == "running" ]] || fail "alpha should be running: $json"
[[ "$(echo "$json" | jq -r '.id')" == "alpha" ]] || fail "alpha should be current: $json"

json="$(h list --json)"
[[ "$(echo "$json" | jq -r '.models[] | select(.id=="alpha") | .active')" == "true" ]] || fail "alpha should be active"
[[ "$(echo "$json" | jq -r '.models[] | select(.id=="bravo") | .state')" == "stopped" ]] || fail "bravo should be stopped"

# Switching models stops the previous one.
h start bravo >/dev/null || fail "start bravo failed"
wait_port "$port_b" || fail "bravo never listened on $port_b"
json="$(h status --json)"
[[ "$(echo "$json" | jq -r '.id')" == "bravo" ]] || fail "bravo should be current: $json"
if (exec 3<>"/dev/tcp/127.0.0.1/$port_a") 2>/dev/null; then
  exec 3>&- 3<&-
  fail "alpha should have been stopped when bravo started"
fi

# Toggling the current model stops it.
h toggle bravo >/dev/null || fail "toggle bravo failed"
sleep 0.4
json="$(h status --json)"
[[ "$(echo "$json" | jq -r '.state')" == "stopped" ]] || fail "expected stopped after toggle: $json"

# Toggling a stopped model starts it.
h toggle alpha >/dev/null || fail "toggle alpha failed"
wait_port "$port_a" || fail "alpha never came back up"
h stop >/dev/null || fail "stop failed"
sleep 0.4
[[ "$(h status --json | jq -r '.state')" == "stopped" ]] || fail "expected stopped after stop"

# Validation.
h validate >/dev/null 2>&1 || fail "validate rejected the generated config"

echo "helper OK (ports $port_a, $port_b)"
