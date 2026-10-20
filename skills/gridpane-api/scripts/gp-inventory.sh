#!/usr/bin/env bash
#
# gp-inventory.sh - export GridPane servers and sites as JSON and CSV.
#
# Uses the verified list endpoints from the GridPane API Postman collection:
#   GET /server?summary=true   (servers, summarised)
#   GET /site                  (sites)
# Both are overridable with --servers-path / --sites-path.
#
# Usage:
#   gp-inventory.sh [--servers-path PATH] [--sites-path PATH] [--out-dir DIR]
#
# Env fallbacks: GRIDPANE_API_SERVERS_PATH, GRIDPANE_API_SITES_PATH.
# Env for the API: GRIDPANE_API_TOKEN, GRIDPANE_API_URL (passed to gp-api.sh).

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="out"
SERVERS_PATH="${GRIDPANE_API_SERVERS_PATH:-/server?summary=true}"
SITES_PATH="${GRIDPANE_API_SITES_PATH:-/site}"
FORMAT="both"

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [--servers-path PATH] [--sites-path PATH] [--out-dir DIR]

Exports servers and sites from the GridPane API to JSON and CSV. Writes:
  {out-dir}/servers.json, {out-dir}/sites.json
  {out-dir}/servers.csv, {out-dir}/sites.csv, {out-dir}/inventory.csv

Options:
  --servers-path PATH   API path that lists servers (default: ${SERVERS_PATH}).
  --sites-path PATH     API path that lists sites (default: ${SITES_PATH}).
  --out-dir DIR         Output directory (default: ${OUT_DIR}).
  --format json|csv|both  Which outputs to write (default: both).
  -h, --help            Show this help.

Environment:
  GRIDPANE_API_TOKEN, GRIDPANE_API_URL   Passed through to gp-api.sh.

The servers/sites endpoint paths are verified from the GridPane API Postman
collection. The server summary fields are documented there; the site CSV mapping
is best-effort and may need adjusting once a live response is captured.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --servers-path) SERVERS_PATH="${2:-}"; shift 2 ;;
        --sites-path) SITES_PATH="${2:-}"; shift 2 ;;
        --out-dir) OUT_DIR="${2:-}"; shift 2 ;;
        --format) FORMAT="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'error: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ -z "$SERVERS_PATH" || -z "$SITES_PATH" ]]; then
    printf 'error: --servers-path and --sites-path must not be empty\n' >&2
    exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
    printf 'error: jq is required\n' >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

if [[ "$FORMAT" == "json" || "$FORMAT" == "both" ]]; then
    "$SCRIPT_DIR/gp-api.sh" GET "$SERVERS_PATH" > "$OUT_DIR/servers.json"
    "$SCRIPT_DIR/gp-api.sh" GET "$SITES_PATH" > "$OUT_DIR/sites.json"
    printf 'wrote %s/servers.json and %s/sites.json\n' "$OUT_DIR" "$OUT_DIR" >&2
fi

if [[ "$FORMAT" == "csv" || "$FORMAT" == "both" ]]; then
    servers_json="$OUT_DIR/servers.json"
    sites_json="$OUT_DIR/sites.json"
    [[ -s "$servers_json" ]] || "$SCRIPT_DIR/gp-api.sh" GET "$SERVERS_PATH" > "$servers_json"
    [[ -s "$sites_json" ]] || "$SCRIPT_DIR/gp-api.sh" GET "$SITES_PATH" > "$sites_json"

    # Server summary fields are documented in the collection:
    # id, label, ip, region, sub_id, subdomain, webserver, database.
    jq -r '
        ["id","label","ip","region","subdomain","webserver","database"],
        (.[]? | [
            (.id // ""),
            (.label // ""),
            (.ip // ""),
            (.region // ""),
            (.subdomain // ""),
            (.webserver // ""),
            (.database // "")
        ]) | @csv
    ' "$servers_json" > "$OUT_DIR/servers.csv"

    # Site list fields are not documented in the collection; this mapping is
    # best-effort until a live response confirms them.
    jq -r '
        ["domain","server_id","php_version","stack","ssl"],
        (.[]? | [
            (.domain // .url // .site // ""),
            (.server_id // .server // ""),
            (.php_version // .php // ""),
            (.stack // .server_stack // ""),
            (.ssl // .ssl_status // .sslEnabled // "")
        ]) | @csv
    ' "$sites_json" > "$OUT_DIR/sites.csv"
    cp "$OUT_DIR/sites.csv" "$OUT_DIR/inventory.csv"

    printf 'wrote %s/servers.csv, %s/sites.csv and %s/inventory.csv\n' \
        "$OUT_DIR" "$OUT_DIR" "$OUT_DIR" >&2
fi
