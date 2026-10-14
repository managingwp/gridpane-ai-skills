#!/usr/bin/env bash
#
# scrape-docs.sh - read-only snapshot index of the GridPane Knowledge Base.
#
# Enumerates /kb/ URLs from the GridPane sitemap, fetches each page (or reads a
# local cache in --offline mode), and writes a JSON manifest of
# url/title/lastmod/fetched_at/sha256. Optionally converts each page to Markdown
# with pandoc into the cache directory.
#
# This script only reads the public website. It never touches a GridPane server
# and never modifies the fetched site. Raw HTML/Markdown stays in the (gitignored)
# cache directory; only the manifest is meant to be committed.
#
# Usage: scrape-docs.sh [options]
#   --sitemap URL|FILE   Sitemap to read (default https://gridpane.com/sitemap.xml)
#   --out FILE           Write the manifest here (default stdout)
#   --cache DIR          Cache directory (default out/gridpane-docs-cache)
#   --limit N            Only process the first N /kb/ URLs
#   --delay SECONDS      Delay between fetches (default 1)
#   --offline            Do not fetch; read pages from the cache only
#   --no-convert         Skip HTML -> Markdown conversion
#   -h, --help           Show this help and exit
#
# Exit status: 0 on success, 2 on usage error, 1 if the sitemap cannot be read.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SITEMAP="https://gridpane.com/sitemap.xml"
OUT=""
CACHE="out/gridpane-docs-cache"
LIMIT=0
DELAY=1
OFFLINE=0
CONVERT=1
UA="gridpane-ai-skills-docs-scraper/1.0 (+https://github.com/managingwp/gridpane-ai-skills)"

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Read-only snapshot index of the GridPane Knowledge Base. Enumerates /kb/ URLs
from the sitemap and writes a JSON manifest of
url/title/lastmod/fetched_at/sha256.

Options:
  --sitemap URL|FILE   Sitemap to read (default ${SITEMAP})
  --out FILE           Write the manifest here (default stdout)
  --cache DIR          Cache directory (default ${CACHE})
  --limit N            Only process the first N /kb/ URLs
  --delay SECONDS      Delay between fetches (default ${DELAY})
  --offline            Do not fetch; read pages from the cache only
  --no-convert         Skip HTML -> Markdown conversion
  -h, --help           Show this help and exit

Cache file names are the URL slug: strip the scheme, then replace every run of
non-alphanumeric characters with "_" (e.g.
https://gridpane.com/kb/foo-bar/ -> gridpane_com_kb_foo_bar).
EOF
}

log() { printf '%s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
json_escape() { printf '%s' "${1:-}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

slugify() {
    printf '%s' "$1" | sed -E 's#^https?://##; s#[^A-Za-z0-9]+#_#g; s#_+$##'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sitemap) SITEMAP="${2:?--sitemap needs a value}"; shift 2 ;;
        --out)     OUT="${2:?--out needs a value}"; shift 2 ;;
        --cache)   CACHE="${2:?--cache needs a value}"; shift 2 ;;
        --limit)   LIMIT="${2:?--limit needs a value}"; shift 2 ;;
        --delay)   DELAY="${2:?--delay needs a value}"; shift 2 ;;
        --offline) OFFLINE=1; shift ;;
        --no-convert) CONVERT=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) log "error: unknown option: $1"; usage >&2; exit 2 ;;
    esac
done

# --- read the sitemap -------------------------------------------------------

if [[ -f "$SITEMAP" ]]; then
    SITEMAP_XML="$(cat "$SITEMAP")"
else
    if ! SITEMAP_XML="$(curl -fsSL --retry 3 --max-time 30 -A "$UA" "$SITEMAP")"; then
        log "error: could not fetch sitemap: $SITEMAP"
        exit 1
    fi
fi

# Build a TSV of "url<TAB>lastmod" for /kb/ entries.
SITEMAP_TSV="$(printf '%s\n' "$SITEMAP_XML" | awk '
    /<url>/ { url=""; lm="" }
    /<loc>/ { l=$0; sub(/.*<loc>/,"",l); sub(/<\/loc>.*/,"",l); url=l }
    /<lastmod>/ { m=$0; sub(/.*<lastmod>/,"",m); sub(/<\/lastmod>.*/,"",m); lm=m }
    /<\/url>/ { if (url != "") print url "\t" lm }
' | grep '/kb/' | sort -u)"

if [[ -z "$SITEMAP_TSV" ]]; then
    log "error: no /kb/ URLs found in $SITEMAP"
    exit 1
fi

# --- process each page ------------------------------------------------------

mkdir -p "$CACHE"
ENTRIES="$(mktemp)"
trap 'rm -f "$ENTRIES"' EXIT

count=0
while IFS=$'\t' read -r url lastmod; do
    [[ -n "$url" ]] || continue
    if [[ "$LIMIT" -gt 0 && "$count" -ge "$LIMIT" ]]; then
        break
    fi

    slug="$(slugify "$url")"
    htmlfile="$CACHE/$slug.html"

    if [[ "$OFFLINE" -eq 1 ]]; then
        if [[ ! -f "$htmlfile" ]]; then
            log "offline: no cache for $url (expected $htmlfile)"
            continue
        fi
        html="$(cat "$htmlfile")"
    else
        if ! html="$(curl -fsSL --retry 3 --max-time 30 -A "$UA" "$url")"; then
            log "fetch failed: $url"
            continue
        fi
        printf '%s' "$html" > "$htmlfile"
        sleep "$DELAY"
    fi

    title="$(printf '%s' "$html" | grep -oE '<title>[^<]*</title>' | head -1 | sed -E 's#</?title>##g')"
    sha="$(printf '%s' "$html" | sha256sum | cut -d' ' -f1)"
    fetched="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    if [[ "$CONVERT" -eq 1 ]] && have pandoc; then
        printf '%s' "$html" | pandoc -f html -t gfm -o "$CACHE/$slug.md" 2>/dev/null || true
    fi

    printf '{"url":"%s","title":"%s","lastmod":"%s","fetched_at":"%s","sha256":"%s"}\n' \
        "$(json_escape "$url")" "$(json_escape "$title")" "$(json_escape "$lastmod")" \
        "$(json_escape "$fetched")" "$(json_escape "$sha")" >> "$ENTRIES"
    count=$((count + 1))
done <<<"$SITEMAP_TSV"

# --- emit the manifest ------------------------------------------------------

emit_manifest() {
    printf '[\n'
    if [[ -s "$ENTRIES" ]]; then
        awk 'BEGIN { n=0 } { n++; printf "%s%s\n", (n > 1 ? "," : ""), $0 }' "$ENTRIES"
    fi
    printf ']\n'
}

if [[ -n "$OUT" ]]; then
    emit_manifest > "$OUT"
    log "wrote $count entries to $OUT"
else
    emit_manifest
    log "wrote $count entries to stdout"
fi
