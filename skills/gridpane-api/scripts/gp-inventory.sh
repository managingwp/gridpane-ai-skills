#!/usr/bin/env bash
#
# gp-inventory.sh - export GridPane servers and sites as JSON and CSV.
#
# The servers and sites list endpoint paths must come from the GridPane API
# documentation (the Postman collection). They are required here rather than
# baked in, because the exact paths are not verified in the GridPane KB.
#
# Usage:
#   gp-inventory.sh --servers-path /servers --sites-path /sites [--out-dir DIR]
#
# Env fallbacks: GRIDPANE_API_SERVERS_PATH, GRIDPANE_API_SITES_PATH.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="out"
SERVERS_PATH="${GRIDPANE_API_SERVERS_PATH:-}"
SITES_PATH="${GRIDPANE_API_SITES_PATH:-}"
FORMAT="both"

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} --servers-path PATH --sites-path PATH [--out-dir DIR]

Exports servers and sites from the GridPane API to JSON and CSV. Writes:
  {out-dir}/servers.json, {out-dir}/sites.json
  {out-dir}/inventory.csv

Options:
  --servers-path PATH   API path that lists servers (required).
  --sites-path PATH     API path that lists sites (required).
  --out-dir DIR         Output directory (default: ${OUT_DIR}).
  --format json|csv|both  Which outputs to write (default: both).
  -h, --help            Show this help.

Environment:
  GRIDPANE_API_TOKEN, GRIDPANE_API_URL   Passed through to gp-api.sh.

The servers/sites endpoint paths and response field names are not verified in
the GridPane KB; confirm them from the Postman API collection. The CSV mapping
below is a best-effort shape and may need adjusting.
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
    printf 'error: --servers-path and --sites-path are required\n' >&2
    printf '       (confirm them from the GridPane API Postman collection)\n' >&2
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
    sites_json="$OUT_DIR/sites.json"
    if [[ ! -s "$sites_json" ]]; then
        "$SCRIPT_DIR/gp-api.sh" GET "$SITES_PATH" > "$sites_json"
    fi
    # Best-effort field mapping; adjust to the confirmed response shape.
    {
        printf 'domain,server,php_version,stack,ssl\n'
        jq -r '
            .[]? |
            [
                (.domain // .site // .url // ""),
                (.server // .server_name // ""),
                (.php_version // .php // ""),
                (.stack // .server_stack // ""),
                (.ssl // .ssl_status // .sslEnabled // "")
            ] | @csv
        ' "$sites_json"
    } > "$OUT_DIR/inventory.csv"
    printf 'wrote %s/inventory.csv\n' "$OUT_DIR" >&2
fi
