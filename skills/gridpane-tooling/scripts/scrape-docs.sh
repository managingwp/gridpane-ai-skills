#!/usr/bin/env bash
#
# scrape-docs.sh - read-only index of the GridPane Knowledge Base.
#
# Two sources:
#
#   api      (default) The public WordPress REST feed for the `kb` post type:
#            /wp-json/wp/v2/kb returns every KB article's title, slug, link,
#            last-modified time, category ids and full rendered body. 387 posts
#            in 4 requests at per_page=100, versus 387 individual page fetches
#            for the sitemap source.
#   sitemap  Enumerate /kb/ URLs from the sitemap and fetch each page.
#
# Both write a JSON manifest of url/title/lastmod/fetched_at/sha256, plus the
# api-only fields modified/categories and a per-entry source. sha256 is the hash
# of the fetched artifact: the page HTML for --source sitemap, the post's
# content.rendered for --source api. It is there to detect change between runs.
#
# Raw JSON and HTML stay in the (gitignored) cache directory; only the manifest
# is meant to be committed. No GridPane page text is rehosted.
#
# This script only reads public endpoints. It never touches a GridPane server
# and never modifies the fetched site.
#
# Usage: scrape-docs.sh [options]
#   --source api|sitemap Which index to build (default api)
#   --base URL           Site root (default https://gridpane.com)
#   --sitemap URL|FILE   Sitemap to read (default https://gridpane.com/sitemap.xml)
#   --out FILE           Write the manifest here (default stdout)
#   --cache DIR          Cache directory (default out/gridpane-docs-cache)
#   --page-size N        API page size, capped at 100 (default 100)
#   --since DATE         API only: pass modified_after=DATE (incremental refresh)
#   --limit N            Only process the first N entries (search: result cap)
#   --search QUERY       One-request KB lookup: print slug/modified/url/title
#   --json               With --search: emit the raw result array instead of TSV
#   --delay SECONDS      Delay between fetches (default 1)
#   --offline            Do not fetch; read pages from the cache only
#   --no-convert         Skip HTML -> Markdown conversion (sitemap source)
#   -h, --help           Show this help and exit
#
# Exit status: 0 on success, 2 on usage error, 1 if the source cannot be read.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SOURCE="api"
BASE="https://gridpane.com"
SITEMAP="https://gridpane.com/sitemap.xml"
OUT=""
CACHE="out/gridpane-docs-cache"
PAGE_SIZE=100
SINCE=""
LIMIT=0
DELAY=1
OFFLINE=0
CONVERT=1
SEARCH=""
JSON_OUT=0
UA="gridpane-ai-skills-docs-scraper/1.1 (+https://github.com/managingwp/gridpane-ai-skills)"

WP_TOTAL=""
WP_TOTAL_PAGES=""
PAGE_JSON=""

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Read-only index of the GridPane Knowledge Base. Builds a JSON manifest of
url/title/lastmod/fetched_at/sha256 (plus modified/categories for the api
source) from either the public WordPress REST feed or the sitemap.

Options:
  --source api|sitemap Which index to build (default ${SOURCE})
  --base URL           Site root (default ${BASE})
  --sitemap URL|FILE   Sitemap to read (default ${SITEMAP})
  --out FILE           Write the manifest here (default stdout)
  --cache DIR          Cache directory (default ${CACHE})
  --page-size N        API page size, capped at 100 (default ${PAGE_SIZE})
  --since DATE         API only: pass modified_after=DATE (incremental refresh)
  --limit N            Only process the first N entries (search: result cap)
  --search QUERY       One-request KB lookup: print slug, modified, url, title
  --json               With --search: emit the raw result array instead of TSV
  --delay SECONDS      Delay between fetches (default ${DELAY})
  --offline            Do not fetch; read pages from the cache only
  --no-convert         Skip HTML -> Markdown conversion (sitemap source)
  -h, --help           Show this help and exit

Manifest shape: {source, fetched_at, count, entries:[…]}; a --since run also
carries "since". Entries are sorted by url so diffs stay readable.

Cache file names: sitemap pages are the URL slug (strip the scheme, then
replace every run of non-alphanumeric characters with "_"); API pages are
api-page-<N>.json (or api-since-<date>-page-<N>.json), and the category term
map is api-kbcategories-<N>.json.
EOF
}

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
json_escape() { printf '%s' "${1:-}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

slugify() {
    printf '%s' "$1" | sed -E 's#^https?://##; s#[^A-Za-z0-9]+#_#g; s#_+$##'
}

# Multibyte characters are built here so shellcheck does not read them as
# unbalanced shell quotes (SC1112).
RSQUO="$(printf '\xe2\x80\x99')"
LSQUO="$(printf '\xe2\x80\x98')"
NDASH="$(printf '\xe2\x80\x93')"
MDASH="$(printf '\xe2\x80\x94')"
LDQUO="$(printf '\xe2\x80\x9c')"
RDQUO="$(printf '\xe2\x80\x9d')"
ELLIPSIS="$(printf '\xe2\x80\xa6')"

# Decode the handful of entities the KB actually uses. &amp; is decoded last so
# a double-escaped entity (&amp;#8217;) is not decoded twice.
decode_entities() {
    sed -e 's/<[^>]*>//g' \
        -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' \
        -e "s/&#0*39;/'/g" -e 's/&apos;/'"'"'/g' \
        -e "s/&#8217;/${RSQUO}/g" -e "s/&#8216;/${LSQUO}/g" \
        -e "s/&#8220;/${LDQUO}/g" -e "s/&#8221;/${RDQUO}/g" \
        -e "s/&#8211;/${NDASH}/g" -e "s/&#8212;/${MDASH}/g" \
        -e "s/&#8230;/${ELLIPSIS}/g" \
        -e 's/&#0*38;/\&/g' \
        -e 's/&nbsp;/ /g' -e 's/&amp;/\&/g'
}

# --- search -----------------------------------------------------------------

# One request, no crawl. The query is URL-encoded through jq so a space or a
# quote in the search term cannot break the URL.
search_kb() {
    local enc per url json count slug modified link title
    enc="$(jq -rn --arg q "$SEARCH" '$q|@uri')"
    per="$LIMIT"
    if [[ "$per" -le 0 ]]; then
        per=20
    elif [[ "$per" -gt 100 ]]; then
        per=100
    fi

    url="$BASE/wp-json/wp/v2/kb?search=$enc&per_page=$per"
    url="$url&_fields=slug,link,title,modified,kbcategories"

    if ! json="$(curl -fsSL --retry 3 --max-time 30 -A "$UA" "$url")"; then
        die "search request failed: $url"
    fi

    if [[ "$JSON_OUT" -eq 1 ]]; then
        jq 'sort_by(.modified) | reverse' <<<"$json"
        return 0
    fi

    count="$(jq 'length' <<<"$json")"
    if [[ "$count" -eq 0 ]]; then
        log "no matches"
        return 0
    fi

    while IFS=$'\t' read -r slug modified link title; do
        title="$(printf '%s' "$title" | decode_entities)"
        printf '%s\t%s\t%s\t%s\n' "$slug" "$modified" "$link" "$title"
    done < <(jq -r 'sort_by(.modified) | reverse | .[]
        | [.slug, .modified, .link, (.title.rendered // "")]
        | @tsv' <<<"$json")
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source)      SOURCE="${2:?--source needs a value}"; shift 2 ;;
        --base)        BASE="${2:?--base needs a value}"; shift 2 ;;
        --sitemap)     SITEMAP="${2:?--sitemap needs a value}"; shift 2 ;;
        --out)         OUT="${2:?--out needs a value}"; shift 2 ;;
        --cache)       CACHE="${2:?--cache needs a value}"; shift 2 ;;
        --page-size)   PAGE_SIZE="${2:?--page-size needs a value}"; shift 2 ;;
        --since)       SINCE="${2:?--since needs a value}"; shift 2 ;;
        --limit)       LIMIT="${2:?--limit needs a value}"; shift 2 ;;
        --search)      SEARCH="${2:?--search needs a value}"; shift 2 ;;
        --json)        JSON_OUT=1; shift ;;
        --delay)       DELAY="${2:?--delay needs a value}"; shift 2 ;;
        --offline)     OFFLINE=1; shift ;;
        --no-convert)  CONVERT=0; shift ;;
        -h|--help)     usage; exit 0 ;;
        *) log "error: unknown option: $1"; usage >&2; exit 2 ;;
    esac
done

case "$SOURCE" in
    api|sitemap) ;;
    *) log "error: --source must be api or sitemap"; exit 2 ;;
esac
[[ "$PAGE_SIZE" =~ ^[0-9]+$ ]] || die "--page-size must be a number"
if [[ "$PAGE_SIZE" -gt 100 ]]; then
    log "warning: --page-size capped at 100 (the REST API's maximum)"
    PAGE_SIZE=100
fi
[[ "$PAGE_SIZE" -gt 0 ]] || die "--page-size must be greater than 0"
[[ "$LIMIT" =~ ^[0-9]+$ ]] || die "--limit must be a number"
have jq || die "jq is required"

if [[ -n "$SEARCH" ]]; then
    if [[ "$SOURCE" != "api" ]]; then
        log "error: --search needs --source api"
        exit 2
    fi
    if [[ -n "$OUT" ]]; then
        log "error: --search cannot be combined with --out"
        exit 2
    fi
    if [[ "$OFFLINE" -eq 1 ]]; then
        log "error: --search cannot be combined with --offline"
        exit 2
    fi
    search_kb
    exit 0
fi

if [[ "$JSON_OUT" -eq 1 ]]; then
    log "error: --json needs --search"
    exit 2
fi

mkdir -p "$CACHE"
FETCHED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

ENTRIES="$(mktemp)"
ENTARRAY="$(mktemp)"
CATTMP="$(mktemp)"
CATMAP="$(mktemp)"
trap 'rm -f "$ENTRIES" "$ENTARRAY" "$CATTMP" "$CATMAP" "$CACHE"/*.tmp' EXIT

# --- api source -------------------------------------------------------------

api_page_file() {
    if [[ -n "$SINCE" ]]; then
        printf '%s/api-since-%s-page-%s.json' "$CACHE" "$(slugify "$SINCE")" "$1"
    else
        printf '%s/api-page-%s.json' "$CACHE" "$1"
    fi
}

api_cat_file() { printf '%s/api-kbcategories-%s.json' "$CACHE" "$1"; }

api_url() {
    local url
    url="$BASE/wp-json/wp/v2/kb?per_page=$PAGE_SIZE&page=$1"
    url="$url&_fields=slug,link,modified,title,kbcategories,content"
    if [[ -n "$SINCE" ]]; then
        url="$url&modified_after=$SINCE"
    fi
    printf '%s' "$url"
}

# Load one API page into PAGE_JSON. Returns 1 when the page cannot be read.
fetch_api_page() {
    local page="$1" file url hdr total pages
    file="$(api_page_file "$page")"

    if [[ "$OFFLINE" -eq 1 ]]; then
        if [[ ! -f "$file" ]]; then
            log "offline: no cache for API page $page (expected $file)"
            return 1
        fi
        PAGE_JSON="$(cat "$file")"
        return 0
    fi

    url="$(api_url "$page")"
    hdr="$(mktemp)"
    if ! curl -fsSL --retry 3 --max-time 60 -A "$UA" -D "$hdr" \
            -o "$file.tmp" "$url"; then
        rm -f "$hdr" "$file.tmp"
        log "fetch failed: $url"
        return 1
    fi

    total="$(awk 'tolower($1)=="x-wp-total:"{print $2}' "$hdr" | tr -d '\r' | tail -1)"
    pages="$(awk 'tolower($1)=="x-wp-totalpages:"{print $2}' "$hdr" | tr -d '\r' | tail -1)"
    [[ -n "$total" ]] && WP_TOTAL="$total"
    [[ -n "$pages" ]] && WP_TOTAL_PAGES="$pages"
    rm -f "$hdr"
    mv "$file.tmp" "$file"

    PAGE_JSON="$(cat "$file")"
    sleep "$DELAY"
}

# Build an id -> name map for kbcategories so a manifest entry carries readable
# category names instead of bare term ids. Falls back to ids when unavailable.
api_categories() {
    local page=1 file url
    : > "$CATTMP"
    while :; do
        file="$(api_cat_file "$page")"
        if [[ "$OFFLINE" -eq 1 ]]; then
            if [[ ! -f "$file" ]]; then
                [[ "$page" -eq 1 ]] && log "offline: no cached KB categories"
                break
            fi
        else
            url="$BASE/wp-json/wp/v2/kbcategories?per_page=100&page=$page&_fields=id,name"
            if ! curl -fsSL --retry 3 --max-time 30 -A "$UA" -o "$file.tmp" "$url"; then
                rm -f "$file.tmp"
                log "warning: could not fetch KB categories; entries will carry term ids"
                break
            fi
            mv "$file.tmp" "$file"
            sleep "$DELAY"
        fi
        cat "$file" >> "$CATTMP"
        if [[ "$(jq 'length' < "$file")" -lt 100 ]]; then
            break
        fi
        page=$((page + 1))
    done

    if [[ -s "$CATTMP" ]]; then
        jq -s 'add | map({key:(.id|tostring), value:.name}) | from_entries' \
            "$CATTMP" > "$CATMAP" || printf '{}\n' > "$CATMAP"
    else
        printf '{}\n' > "$CATMAP"
    fi
}

api_index() {
    local page=1 count=0 n rec sha title

    api_categories
    : > "$ENTRIES"

    while :; do
        if ! fetch_api_page "$page"; then
            if [[ "$page" -eq 1 ]]; then
                die "could not read API page 1 from $BASE"
            fi
            log "warning: stopping after page $((page - 1))"
            break
        fi

        n="$(jq 'length' <<<"$PAGE_JSON")"
        [[ "$n" -eq 0 ]] && break

        # Emit each post as one JSONL record, with the body hashed then dropped.
        jq -c --slurpfile m "$CATMAP" '
            ($m[0]) as $cm
            | .[]
            | {
                url: .link,
                title: (.title.rendered // ""),
                lastmod: "",
                modified: (.modified // ""),
                categories: ((.kbcategories // [])
                    | map($cm[(tostring)] // ("term-" + (tostring)))),
                source: "api",
                text: (.content.rendered // "")
              }' <<<"$PAGE_JSON" > "$CACHE/api-page-$$.jsonl"

        while IFS= read -r rec; do
            [[ -n "$rec" ]] || continue
            sha="$(jq -jr '.text' <<<"$rec" | sha256sum | cut -d' ' -f1)"
            title="$(jq -r '.title' <<<"$rec" | decode_entities)"
            jq -c --arg sha "$sha" --arg title "$title" --arg fetched "$FETCHED" '
                del(.text)
                | .title = $title
                | .sha256 = $sha
                | .fetched_at = $fetched' <<<"$rec" >> "$ENTRIES"
        done < "$CACHE/api-page-$$.jsonl"
        rm -f "$CACHE/api-page-$$.jsonl"

        count=$((count + n))
        if [[ "$LIMIT" -gt 0 && "$count" -ge "$LIMIT" ]]; then
            break
        fi
        if [[ -n "$WP_TOTAL_PAGES" && "$page" -ge "$WP_TOTAL_PAGES" ]]; then
            break
        fi
        if [[ "$n" -lt "$PAGE_SIZE" ]]; then
            break
        fi
        page=$((page + 1))
    done
}

# --- sitemap source ---------------------------------------------------------

sitemap_tsv() {
    local xml
    if [[ -f "$SITEMAP" ]]; then
        xml="$(cat "$SITEMAP")"
    else
        if ! xml="$(curl -fsSL --retry 3 --max-time 30 -A "$UA" "$SITEMAP")"; then
            die "could not fetch sitemap: $SITEMAP"
        fi
    fi

    printf '%s\n' "$xml" | awk '
        /<url>/ { url=""; lm="" }
        /<loc>/ { l=$0; sub(/.*<loc>/,"",l); sub(/<\/loc>.*/,"",l); url=l }
        /<lastmod>/ { m=$0; sub(/.*<lastmod>/,"",m); sub(/<\/lastmod>.*/,"",m); lm=m }
        /<\/url>/ { if (url != "") print url "\t" lm }
    ' | grep '/kb/' | sort -u
}

sitemap_index() {
    local tsv url lastmod slug htmlfile html title sha count=0

    tsv="$(sitemap_tsv)"
    [[ -n "$tsv" ]] || die "no /kb/ URLs found in $SITEMAP"
    : > "$ENTRIES"

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

        title="$(printf '%s' "$html" | grep -oE '<title>[^<]*</title>' | head -1 \
            | sed -E 's#</?title>##g' | decode_entities)"
        sha="$(printf '%s' "$html" | sha256sum | cut -d' ' -f1)"

        if [[ "$CONVERT" -eq 1 ]] && have pandoc; then
            printf '%s' "$html" | pandoc -f html -t gfm -o "$CACHE/$slug.md" 2>/dev/null || true
        fi

        printf '{"url":"%s","title":"%s","lastmod":"%s","modified":"","categories":[],"source":"sitemap","fetched_at":"%s","sha256":"%s"}\n' \
            "$(json_escape "$url")" "$(json_escape "$title")" "$(json_escape "$lastmod")" \
            "$(json_escape "$FETCHED")" "$(json_escape "$sha")" >> "$ENTRIES"
        count=$((count + 1))
    done <<<"$tsv"
}

# --- build ------------------------------------------------------------------

if [[ "$SOURCE" == "api" ]]; then
    api_index
else
    sitemap_index
fi

if [[ "$LIMIT" -gt 0 ]]; then
    head -n "$LIMIT" "$ENTRIES" > "$ENTRIES.cut"
    mv "$ENTRIES.cut" "$ENTRIES"
fi

jq -s 'sort_by(.url)' "$ENTRIES" > "$ENTARRAY"
count="$(jq 'length' "$ENTARRAY")"

if [[ "$SOURCE" == "api" && "$OFFLINE" -eq 0 && "$LIMIT" -eq 0 && -z "$SINCE" \
        && -n "$WP_TOTAL" && "$count" -ne "$WP_TOTAL" ]]; then
    log "warning: manifest has $count entries but the API reported X-WP-Total: $WP_TOTAL"
fi
if [[ -n "$WP_TOTAL" ]]; then
    log "API reports X-WP-Total: $WP_TOTAL"
fi

emit_manifest() {
    jq -n \
        --arg source "$SOURCE" \
        --arg base "$BASE" \
        --arg fetched "$FETCHED" \
        --arg since "$SINCE" \
        --argjson total "$count" \
        --slurpfile e "$ENTARRAY" \
        '{source: $source}
         + (if $source == "api" then {base: $base} else {} end)
         + (if $since != "" then {since: $since} else {} end)
         + {fetched_at: $fetched, count: $total, entries: $e[0]}'
}

if [[ -n "$OUT" ]]; then
    emit_manifest > "$OUT"
    log "wrote $count entries to $OUT"
else
    emit_manifest
    log "wrote $count entries to stdout"
fi
