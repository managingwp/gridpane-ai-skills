#!/usr/bin/env bash
#
# gp-api.sh - thin wrapper around the GridPane REST API.
#
# Reads the token from GRIDPANE_API_TOKEN and sends it as a Bearer token. Never
# prints the token. Defaults to GET; any mutating method requires --yes.
#
# Usage: gp-api.sh <METHOD> <PATH> [--data JSON] [--yes] [--header 'N: V'] [--help]

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
BASE_URL="${GRIDPANE_API_URL:-https://my.gridpane.com/oauth/api/v1}"
TOKEN="${GRIDPANE_API_TOKEN:-}"
MAX_RETRIES=3

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} <METHOD> <PATH> [options]

Call the GridPane REST API. Base URL: GRIDPANE_API_URL
(default ${BASE_URL}).

Arguments:
  METHOD            GET, POST, PUT, PATCH or DELETE.
  PATH              Path appended to the base URL, e.g. /backups/purge/42.

Options:
  --data JSON       Request body (sets Content-Type: application/json).
  --header 'N: V'   Add a request header. Repeatable.
  --yes             Required for any non-GET method.
  -h, --help        Show this help and exit.

Environment:
  GRIDPANE_API_TOKEN   Required. Sent as: Authorization: Bearer <token>.
  GRIDPANE_API_URL     Optional base URL.

The token is never written to stdout or stderr.
EOF
}

METHOD=""
API_PATH=""
DATA=""
CONFIRM=0
EXTRA_HEADERS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --data) DATA="${2:-}"; shift 2 ;;
        --header) EXTRA_HEADERS+=("${2:-}"); shift 2 ;;
        --yes) CONFIRM=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --*) printf 'error: unknown option: %s\n' "$1" >&2; exit 2 ;;
        *)
            if [[ -z "$METHOD" ]]; then
                METHOD="$1"
            elif [[ -z "$API_PATH" ]]; then
                API_PATH="$1"
            else
                printf 'error: unexpected argument: %s\n' "$1" >&2
                exit 2
            fi
            shift
            ;;
    esac
done

if [[ -z "$METHOD" || -z "$API_PATH" ]]; then
    printf 'error: METHOD and PATH are required\n' >&2
    usage >&2
    exit 2
fi

METHOD="${METHOD^^}"
case "$METHOD" in
    GET|POST|PUT|PATCH|DELETE) ;;
    *) printf 'error: unsupported method: %s\n' "$METHOD" >&2; exit 2 ;;
esac

if [[ -z "$TOKEN" ]]; then
    printf 'error: GRIDPANE_API_TOKEN is not set\n' >&2
    exit 2
fi

if [[ "$METHOD" != "GET" && "$CONFIRM" -ne 1 ]]; then
    printf 'error: %s is a mutating method; pass --yes to confirm\n' "$METHOD" >&2
    exit 2
fi

url="${BASE_URL%/}/${API_PATH#/}"

curl_args=(-sS -X "$METHOD")
curl_args+=(-H "Authorization: Bearer ${TOKEN}")
curl_args+=(-H "Accept: application/json")
for h in "${EXTRA_HEADERS[@]:-}"; do
    [[ -n "$h" ]] && curl_args+=(-H "$h")
done
if [[ -n "$DATA" ]]; then
    curl_args+=(-H "Content-Type: application/json")
    curl_args+=(--data "$DATA")
fi

body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT

attempt=0
while true; do
    if ! code="$(curl "${curl_args[@]}" -o "$body_file" -w '%{http_code}' "$url")"; then
        printf 'error: request to %s failed\n' "$url" >&2
        exit 1
    fi
    if [[ "$code" == "429" && "$attempt" -lt "$MAX_RETRIES" ]]; then
        attempt=$(( attempt + 1 ))
        sleep $(( attempt * 2 ))
        continue
    fi
    break
done

cat "$body_file"

if [[ "$code" -ge 400 ]]; then
    printf 'error: HTTP %s from %s %s\n' "$code" "$METHOD" "$url" >&2
    exit 1
fi
