#!/usr/bin/env bash
#
# test_gp_api.sh - tests for the GridPane API scripts using local fixtures.
#
# Starts a throwaway HTTP server on localhost and points GRIDPANE_API_URL at it,
# so the tests never call the live GridPane API.
#
# Usage: test_gp_api.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_DIR="$(cd "$SCRIPT_DIR/../../skills/gridpane-api/scripts" && pwd)"
GP_API="$API_DIR/gp-api.sh"
GP_INV="$API_DIR/gp-inventory.sh"

WORK="$(mktemp -d)"
SERVER_PID=""

cleanup() {
    [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok: %s\n' "$1"; }

# --- fixtures ---------------------------------------------------------------

mkdir -p "$WORK/www"
printf '{"id":42,"name":"example"}\n' > "$WORK/www/object.json"
cat > "$WORK/www/servers.json" <<'JSON'
[{"id":1,"label":"srv-01","ip":"203.0.113.10","region":"us-east","sub_id":"do-123","subdomain":"abc.gridpane.example.com","webserver":"nginx","database":"percona"}]
JSON
cat > "$WORK/www/sites.json" <<'JSON'
[{"domain":"example.com","server_id":1,"php_version":"8.2","stack":"nginx","ssl":"active"}]
JSON
# Default paths resolve with the query string stripped by the mock server.
cp "$WORK/www/servers.json" "$WORK/www/server"
cp "$WORK/www/sites.json" "$WORK/www/site"

# --- local mock server ------------------------------------------------------

free_port() {
    python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}
PORT="$(free_port)"

( cd "$WORK/www" && python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 ) &
SERVER_PID=$!

# Wait for the server to accept connections.
for _ in $(seq 1 50); do
    if curl -sS -o /dev/null "http://127.0.0.1:$PORT/object.json" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

export GRIDPANE_API_URL="http://127.0.0.1:$PORT"
export GRIDPANE_API_TOKEN="test-token-123"

# --- tests ------------------------------------------------------------------

out="$("$GP_API" GET /object.json)"
[[ "$out" == *'"id":42'* ]] || fail "GET should return the fixture body"
pass "GET returns the body"

[[ "$out" != *"$GRIDPANE_API_TOKEN"* ]] || fail "token must not appear in output"
pass "token is not leaked in output"

set +e
"$GP_API" POST /object.json --data '{"x":1}' >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "POST without --yes should exit 2 (got $rc)"
pass "POST without --yes is refused"

set +e
"$GP_API" GET /missing.json >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "404 should exit non-zero"
pass "HTTP 404 exits non-zero"

set +e
"$GP_API" GET /object.json >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "GET should exit 0 (got $rc)"
pass "GET exits 0"

"$GP_INV" --servers-path /servers.json --sites-path /sites.json --out-dir "$WORK/out" >/dev/null 2>&1
[[ -s "$WORK/out/sites.json" ]] || fail "inventory should write sites.json"
[[ -s "$WORK/out/servers.csv" ]] || fail "inventory should write servers.csv"
[[ -s "$WORK/out/sites.csv" ]] || fail "inventory should write sites.csv"
[[ -s "$WORK/out/inventory.csv" ]] || fail "inventory should write inventory.csv"
grep -q 'example.com' "$WORK/out/inventory.csv" || fail "inventory.csv should contain the site domain"
grep -q 'srv-01' "$WORK/out/servers.csv" || fail "servers.csv should contain the server label"
grep -q 'percona' "$WORK/out/servers.csv" || fail "servers.csv should contain the database field"
pass "inventory exports servers and sites from fixtures"

# The default paths (/server?summary=true, /site) resolve against the mock.
"$GP_INV" --out-dir "$WORK/out2" >/dev/null 2>&1
grep -q 'srv-01' "$WORK/out2/servers.csv" || fail "default servers path should resolve"
grep -q 'example.com' "$WORK/out2/sites.csv" || fail "default sites path should resolve"
pass "inventory uses the verified default paths"

printf '\nAll API script tests passed.\n'
