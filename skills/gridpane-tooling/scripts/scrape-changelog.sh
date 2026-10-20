#!/usr/bin/env bash
#
# scrape-changelog.sh - read-only digest of the GridPane changelog (Upvoty).
#
# The changelog at https://roadmap.gridpane.com/changelog is a JavaScript SPA,
# but it reads a public JSON API. This script resolves the portal, pages through
# that API, and writes a digest manifest of id/title/published_at/tags. It uses
# curl + jq only - no browser, no Node.
#
# The portal endpoint is public and issues a per-session access token; the
# script fetches that token at runtime and never stores it.
#
# Usage: scrape-changelog.sh [options]

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
PORTAL_HOST="roadmap.gridpane.com"
API_BASE="https://core-api.upvotyfeedback.com"
PORTAL_CONFIG=""
CHANGELOG_JSON=""
OUT=""
PER_PAGE=100
MAX_PAGES=0
LIMIT=0
UA="gridpane-ai-skills-changelog-scraper/1.0 (+https://github.com/managingwp/gridpane-ai-skills)"

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Read-only digest of the GridPane changelog. Resolves the public portal, pages
through the changelog API, and writes a JSON digest of
id/title/published_at/tags.

Options:
  --portal-host HOST   Portal host (default ${PORTAL_HOST})
  --api-base URL       API base (default ${API_BASE})
  --portal-config SRC  Portal config JSON: a file path or URL (default derived)
  --changelog-json F   Offline: read a single changelog page from this file
  --out FILE           Write the digest here (default stdout)
  --per-page N         Items per API page (default ${PER_PAGE})
  --max-pages N        Stop after N pages (default: all)
  --limit N            Keep only the first N entries (default: all)
  -h, --help           Show this help and exit

Exit status: 0 on success, 2 on usage error, 1 on failure.
EOF
}

log() { printf '%s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
die() { log "error: $*"; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --portal-host)   PORTAL_HOST="${2:?--portal-host needs a value}"; shift 2 ;;
        --api-base)      API_BASE="${2:?--api-base needs a value}"; shift 2 ;;
        --portal-config) PORTAL_CONFIG="${2:?--portal-config needs a value}"; shift 2 ;;
        --changelog-json) CHANGELOG_JSON="${2:?--changelog-json needs a value}"; shift 2 ;;
        --out)           OUT="${2:?--out needs a value}"; shift 2 ;;
        --per-page)      PER_PAGE="${2:?--per-page needs a value}"; shift 2 ;;
        --max-pages)     MAX_PAGES="${2:?--max-pages needs a value}"; shift 2 ;;
        --limit)         LIMIT="${2:?--limit needs a value}"; shift 2 ;;
        -h|--help)       usage; exit 0 ;;
        *) log "error: unknown option: $1"; usage >&2; exit 2 ;;
    esac
done

have curl || die "curl is required"
have jq || die "jq is required"

append_page() {
    jq -c '.items[] | {id, title, published_at: .publishedAt, tags: ([.tags[]?.label])}'
}

ENTRIES="$(mktemp)"
DEDUP="$(mktemp)"
LIMITED="$(mktemp)"
FINAL="$(mktemp)"
trap 'rm -f "$ENTRIES" "$DEDUP" "$LIMITED" "$FINAL"' EXIT

if [[ -n "$CHANGELOG_JSON" ]]; then
    [[ -f "$CHANGELOG_JSON" ]] || die "changelog file not found: $CHANGELOG_JSON"
    append_page < "$CHANGELOG_JSON" >> "$ENTRIES"
else
    if [[ -n "$PORTAL_CONFIG" && -f "$PORTAL_CONFIG" ]]; then
        portal_json="$(cat "$PORTAL_CONFIG")"
    else
        portal_url="${PORTAL_CONFIG:-$API_BASE/public/projects/$PORTAL_HOST}"
        portal_json="$(curl -fsSL --retry 3 --max-time 30 -A "$UA" "$portal_url")" \
            || die "could not fetch portal config: $portal_url"
    fi

    owner="$(jq -r '.owner // empty' <<<"$portal_json")"
    project="$(jq -r '.id // empty' <<<"$portal_json")"
    token="$(jq -r '.accountSession.accessToken // empty' <<<"$portal_json")"
    [[ -n "$owner" && -n "$project" ]] || die "portal config missing owner/id"

    auth=()
    [[ -n "$token" ]] && auth=(-H "Authorization: Bearer portal_$token")

    page=1
    while :; do
        url="$API_BASE/$owner/projects/$project/changelog?perPage=$PER_PAGE&page=$page"
        if ! page_json="$(curl -fsSL --retry 3 --max-time 30 -A "$UA" "${auth[@]}" "$url")"; then
            log "warning: fetch failed: $url"
            break
        fi
        count="$(jq '.items | length' <<<"$page_json")"
        [[ "$count" -eq 0 ]] && break
        append_page <<<"$page_json" >> "$ENTRIES"
        pages="$(jq -r '.pages // 1' <<<"$page_json")"
        [[ "$MAX_PAGES" -gt 0 && "$page" -ge "$MAX_PAGES" ]] && break
        [[ "$page" -ge "$pages" ]] && break
        page=$((page + 1))
        sleep 1
    done
fi

# Deduplicate by id (keep first), apply the limit, sort newest first.
jq -s 'reduce .[] as $x ([]; if (map(.id) | index($x.id)) then . else . + [$x] end)' \
    "$ENTRIES" > "$DEDUP"
if [[ "$LIMIT" -gt 0 ]]; then
    jq ".[0:$LIMIT]" "$DEDUP" > "$LIMITED"
else
    cp "$DEDUP" "$LIMITED"
fi
jq 'sort_by(.published_at) | reverse' "$LIMITED" > "$FINAL"

emit() {
    jq -n \
        --arg source "https://$PORTAL_HOST/changelog" \
        --arg fetched "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --slurpfile e "$FINAL" \
        '{source: $source, fetched_at: $fetched, count: ($e[0] | length), entries: $e[0]}'
}

if [[ -n "$OUT" ]]; then
    emit > "$OUT"
    log "wrote $(jq 'length' "$FINAL") entries to $OUT"
else
    emit
    log "wrote $(jq 'length' "$FINAL") entries to stdout"
fi
