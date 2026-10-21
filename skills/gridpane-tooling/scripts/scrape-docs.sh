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
# api-only fields modified/published/categories and a per-entry source. sha256 is
# the hash of the fetched artifact: the page HTML for --source sitemap, the
# post's content.rendered for --source api. It is there to detect change between
# runs.
#
# Dates: the REST `date` and `modified` fields are site-local (UTC-4 on
# gridpane.com) and must not be compared with anything else. The manifest stores
# `modified` from modified_gmt and `published` from date_gmt, because those UTC
# values equal the sitemap's lastmod and the page's article:modified_time meta.
# The site sends no Last-Modified or ETag and answers no 304s, so --probe is the
# cheap change check.
#
# Raw JSON and HTML stay in the (gitignored) cache directory; only the manifest
# is meant to be committed. No GridPane page text is rehosted: extracted text is
# written to the cache as <slug>.md and must never be committed.
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
#   --since-last         API only: use the last full run's fetched_at as --since
#   --probe              One request: print the newest modified_gmt and slug
#   --probe-json FILE    With --probe: read a saved response instead of fetching
#   --limit N            Only process the first N entries (search: result cap)
#   --search QUERY       One-request KB lookup: print slug/modified/url/title
#   --json               With --search: emit the raw result array instead of TSV
#   --format text|markdown  With --slug/--all: extract a cached body to text
#   --slug SLUG          Extract one article (by WordPress slug) into the cache
#   --all                Extract every slug present in the cached API pages
#   --dry-run            Print the request URL(s) and exit without fetching
#   --search-json FILE   With --search: read a saved response instead of fetching
#   --delay SECONDS      Delay between fetches (default 10; live runs refuse <10)
#   --snapshot DIR       Read a specific snapshot (default: the newest one)
#   --allow-fast         Permit --delay below 10 (fixtures only, never a live site)
#   --force              Accept a >10% drop in entry count vs the last snapshot
#   --partial            Accept an X-WP-Total mismatch (deliberate partial data)
#   --offline            Do not fetch; read pages from the cache only
#   --no-convert         Skip HTML -> Markdown conversion (sitemap source)
#   -h, --help           Show this help and exit
#
# Snapshots: every live run writes to <cache>/<YYYY-MM-DD>[-N]/ (never into an
# existing snapshot) with its manifest.json, and points <cache>/latest at it. An
# aborted run leaves its directory without manifest.json, which later runs
# ignore. --offline reads the newest snapshot.
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
DELAY=10
OFFLINE=0
CONVERT=1
SEARCH=""
JSON_OUT=0
SLUG=""
EXTRACT_ALL=0
FORMAT=""
DRY_RUN=0
SEARCH_JSON=""
PROBE=0
PROBE_JSON=""
SINCE_LAST=0
SNAPSHOT_DIR=""
ALLOW_FAST=0
FORCE=0
PARTIAL=0
RUN_DIR=""
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
  --since-last         API only: use the last full run's fetched_at as --since
  --probe              One request: print the newest modified_gmt and slug
  --probe-json FILE    With --probe: read a saved response instead of fetching
  --limit N            Only process the first N entries (search: result cap)
  --search QUERY       One-request KB lookup: print slug, modified, url, title
  --json               With --search: emit the raw result array instead of TSV
  --format text|markdown  With --slug/--all: extract a cached body to text
  --slug SLUG          Extract one article (by WordPress slug) into the cache
  --all                Extract every slug present in the cached API pages
  --dry-run            Print the request URL(s) and exit without fetching
  --search-json FILE   With --search: read a saved response instead of fetching
  --delay SECONDS      Delay between fetches (default ${DELAY}; live runs refuse <10)
  --snapshot DIR       Read a specific snapshot (default: the newest one)
  --allow-fast         Permit --delay below 10 (fixtures only, never a live site)
  --force              Accept a >10% drop in entry count vs the last snapshot
  --partial            Accept an X-WP-Total mismatch (deliberate partial data)
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

# The index URL for one API page. Defined before the argument dispatch so
# --dry-run can print it without fetching.
api_url() {
    local url
    url="$BASE/wp-json/wp/v2/kb?per_page=$PAGE_SIZE&page=$1"
    url="$url&_fields=slug,link,modified_gmt,date_gmt,title,kbcategories,content"
    if [[ -n "$SINCE" ]]; then
        url="$url&modified_after=$SINCE"
    fi
    printf '%s' "$url"
}

# --- probe and cursor -------------------------------------------------------

# Cursor written by the last complete live run. Phase 2 promotes this into the
# "latest" pointer for dated snapshots.
cursor_file() { printf '%s/last-run.json' "$CACHE"; }

cursor_fetched_at() {
    local f
    f="$(cursor_file)"
    [[ -f "$f" ]] || die "no previous run recorded in $CACHE (run a full index first)"
    jq -r '.fetched_at // empty' < "$f"
}

write_cursor() {
    jq -n --arg fetched "$FETCHED" --arg source "$SOURCE" \
        --argjson count "$count" --arg manifest "${OUT:-}" \
        --arg snapshot "$(basename "$RUN_DIR")" \
        '{fetched_at: $fetched, source: $source, count: $count, manifest: $manifest, snapshot: $snapshot}' \
        > "$(cursor_file)"
}

# One request that answers "did anything change?". The site sends no
# Last-Modified or ETag (and no 304s), so this tiny payload is the cheapest
# available change check.
probe_url() {
    printf '%s/wp-json/wp/v2/kb?orderby=modified&order=desc&per_page=1&_fields=slug,modified_gmt' \
        "$BASE"
}

probe_kb() {
    local url json modified slug baseline
    url="$(probe_url)"

    if [[ -n "$PROBE_JSON" ]]; then
        [[ -f "$PROBE_JSON" ]] || die "probe fixture not found: $PROBE_JSON"
        json="$(cat "$PROBE_JSON")"
    elif ! json="$(curl -fsSL --retry 3 --max-time 30 -A "$UA" "$url")"; then
        die "probe request failed: $url"
    fi

    modified="$(jq -r '.[0].modified_gmt // empty' <<<"$json")"
    slug="$(jq -r '.[0].slug // empty' <<<"$json")"
    [[ -n "$modified" ]] || die "probe returned no modified_gmt"

    if [[ "$SINCE_LAST" -eq 1 ]]; then
        baseline="$(cursor_fetched_at)"
        if [[ "${modified%Z}" > "${baseline%Z}" ]]; then
            printf '%s\t%s\n' "$modified" "$slug"
            log "changes since $baseline"
        else
            printf 'no changes since %s\n' "$baseline"
        fi
        return 0
    fi

    printf '%s\t%s\n' "$modified" "$slug"
    log "probe: $url"
}

# --- snapshots --------------------------------------------------------------

# Directory to read cached pages from: an explicit --snapshot, the newest dated
# snapshot that has a manifest.json, or the legacy flat cache.
read_dir() {
    local d
    if [[ -n "$SNAPSHOT_DIR" ]]; then
        d="$SNAPSHOT_DIR"
        [[ "$d" = /* ]] || d="$CACHE/$d"
        [[ -d "$d" ]] || die "snapshot not found: $d"
        printf '%s' "$d"
        return 0
    fi
    d="$(snapshot_dirs | tail -1)"
    if [[ -n "$d" && -f "$d/manifest.json" ]]; then
        printf '%s' "$d"
        return 0
    fi
    if compgen -G "$CACHE/api-page-*.json" >/dev/null \
        || compgen -G "$CACHE/*.html" >/dev/null; then
        printf '%s' "$CACHE"
        return 0
    fi
    die "no cached snapshot in $CACHE (run a live index first)"
}

snapshot_dirs() {
    find "$CACHE" -maxdepth 1 -type d -name '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]*' \
        2>/dev/null | sort
}

# A live run always gets a fresh directory: <YYYY-MM-DD>, then -2, -3, … An
# existing snapshot is never written into.
new_snapshot_dir() {
    local base name n=1
    base="$(date -u +%Y-%m-%d)"
    name="$base"
    while [[ -e "$CACHE/$name" ]]; do
        n=$((n + 1))
        name="$base-$n"
    done
    mkdir "$CACHE/$name" || die "could not create $CACHE/$name"
    printf '%s' "$CACHE/$name"
}

# Newest completed snapshot other than the one being built.
previous_snapshot_dir() {
    local d last=""
    while IFS= read -r d; do
        [[ -n "$d" ]] || continue
        [[ "$d" == "$RUN_DIR" ]] && continue
        [[ -f "$d/manifest.json" ]] && last="$d"
    done < <(snapshot_dirs)
    printf '%s' "$last"
}

update_latest() {
    local name
    name="$(basename "$RUN_DIR")"
    rm -f "$CACHE/latest"
    if ! ln -s "$name" "$CACHE/latest" 2>/dev/null; then
        printf '%s\n' "$name" > "$CACHE/latest"
    fi
}

# Refuse a manifest that shrank by more than 10% against the previous snapshot:
# a blocked request or a truncated feed looks exactly like that.
guard_count_drop() {
    local prev prev_count
    prev="$(previous_snapshot_dir)"
    [[ -n "$prev" ]] || return 0
    prev_count="$(jq -r '.count // 0' "$prev/manifest.json" 2>/dev/null || printf '0')"
    [[ "$prev_count" -gt 0 ]] || return 0
    if [[ "$count" -lt $((prev_count * 90 / 100)) ]]; then
        if [[ "$FORCE" -eq 1 ]]; then
            log "warning: entry count dropped from $prev_count to $count (--force given)"
            return 0
        fi
        log "error: entry count dropped from $prev_count to $count (below 90% of $(basename "$prev"))"
        log "       rerun with --force if the drop is real; $(basename "$RUN_DIR") has no manifest"
        return 1
    fi
    return 0
}

# --- search -----------------------------------------------------------------

# One request, no crawl. The query is URL-encoded through jq so a space or a
# quote in the search term cannot break the URL. --search-json reads a saved
# response instead, which is how the offline test exercises this path.
search_url() {
    local enc per
    enc="$(jq -rn --arg q "$SEARCH" '$q|@uri')"
    per="$LIMIT"
    if [[ "$per" -le 0 ]]; then
        per=20
    elif [[ "$per" -gt 100 ]]; then
        per=100
    fi
    printf '%s/wp-json/wp/v2/kb?search=%s&per_page=%s&_fields=slug,link,title,modified_gmt,kbcategories' \
        "$BASE" "$enc" "$per"
}

search_kb() {
    local url json count slug modified link title
    url="$(search_url)"

    if [[ -n "$SEARCH_JSON" ]]; then
        [[ -f "$SEARCH_JSON" ]] || die "search fixture not found: $SEARCH_JSON"
        json="$(cat "$SEARCH_JSON")"
    elif ! json="$(curl -fsSL --retry 3 --max-time 30 -A "$UA" "$url")"; then
        die "search request failed: $url"
    fi

    if [[ "$JSON_OUT" -eq 1 ]]; then
        jq 'sort_by(.modified_gmt) | reverse' <<<"$json"
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
    done < <(jq -r 'sort_by(.modified_gmt) | reverse | .[]
        | [.slug, .modified_gmt, .link, (.title.rendered // "")]
        | @tsv' <<<"$json")
}

# --- extraction -------------------------------------------------------------

# Walk the markup with awk using "<" as the record separator: every record is a
# tag plus the text that follows it up to the next tag. Element bodies for
# script/style/svg/noscript are dropped until their closing tag, so inline CSS
# and SVG paths never reach the output. <p>/<li>/<br>/… become line breaks.
html_to_text() {
    local fmt="$1"
    awk -v fmt="$fmt" '
    BEGIN { RS = "<"; ORS = ""; skip = "" }
    {
        if (NR == 1) { out = out $0; next }
        cend = index($0, ">")
        if (cend == 0) next
        name = tolower(substr($0, 1, cend - 1))
        sub(/[ \t].*$/, "", name)
        text = substr($0, cend + 1)

        if (skip != "") {
            if (name == "/" skip) skip = ""
            next
        }
        if (name == "script" || name == "style" || name == "svg" \
                || name == "noscript" || name == "head") {
            skip = name
            next
        }
        if (name == "br" || name ~ /^\/(p|div|li|tr|h[1-6]|pre|blockquote|section|article|table|ul|ol)$/) {
            out = out "\n"
        } else if (name == "td" || name == "th") {
            out = out (fmt == "markdown" ? "| " : "\t")
        } else if (name == "li" && fmt == "markdown") {
            out = out "- "
        }
        out = out text
    }
    END { printf "%s\n", out }
    '
}

# Print one article body from a snapshot: first the API page caches (exact body,
# no theme chrome), then the sitemap HTML cache.
read_body() {
    local dir="$1" slug="$2" f
    for f in "$dir"/api-page-*.json "$dir"/api-since-*-page-*.json; do
        [[ -f "$f" ]] || continue
        if jq -e --arg s "$slug" 'any(.[]; .slug == $s)' < "$f" >/dev/null 2>&1; then
            jq -r --arg s "$slug" '.[] | select(.slug == $s) | .content.rendered' < "$f"
            return 0
        fi
    done
    for f in "$dir"/*_"$(slugify "$slug")".html; do
        [[ -f "$f" ]] || continue
        cat "$f"
        return 0
    done
    return 1
}

extract_one() {
    local dir="$1" slug="$2" body converter out
    if ! body="$(read_body "$dir" "$slug")"; then
        log "no cached body for slug: $slug"
        return 1
    fi

    if [[ "$FORMAT" == "markdown" ]] && have pandoc; then
        body="$(printf '%s' "$body" | pandoc -f html -t gfm 2>/dev/null)" || body=""
        converter="pandoc"
        if [[ -z "$body" ]]; then
            log "warning: pandoc produced nothing for $slug; using the fallback"
            body="$(read_body "$dir" "$slug" | html_to_text "$FORMAT" | decode_entities)"
            converter="fallback"
        fi
    else
        body="$(printf '%s' "$body" | html_to_text "$FORMAT" | decode_entities)"
        converter="fallback"
    fi

    # Trim per-line indentation the Elementor wrappers leave behind, squeeze
    # repeated blank lines, and drop leading blank lines.
    body="$(printf '%s\n' "$body" \
        | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
        | cat -s | sed -e '/./,$!d')"

    out="$dir/$slug.md"
    printf '%s\n' "$body" > "$out"
    log "wrote $out ($converter, $(wc -c < "$out" | tr -d ' ') bytes)"
}

extract_slugs() {
    local dir
    dir="$(read_dir)"
    if [[ -n "$SLUG" ]]; then
        extract_one "$dir" "$SLUG"
        return
    fi
    if ! compgen -G "$dir/api-page-*.json" >/dev/null; then
        die "--all needs cached API pages; run the index first"
    fi
    jq -r '.[].slug' "$dir"/api-page-*.json | sort -u | while IFS= read -r s; do
        [[ -n "$s" ]] || continue
        extract_one "$dir" "$s" || true
    done
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
        --search-json) SEARCH_JSON="${2:?--search-json needs a value}"; shift 2 ;;
        --dry-run)     DRY_RUN=1; shift ;;
        --probe)       PROBE=1; shift ;;
        --probe-json)  PROBE_JSON="${2:?--probe-json needs a value}"; shift 2 ;;
        --since-last)  SINCE_LAST=1; shift ;;
        --snapshot)    SNAPSHOT_DIR="${2:?--snapshot needs a value}"; shift 2 ;;
        --allow-fast)  ALLOW_FAST=1; shift ;;
        --force)       FORCE=1; shift ;;
        --partial)     PARTIAL=1; shift ;;
        --format)      FORMAT="${2:?--format needs a value}"; shift 2 ;;
        --slug)        SLUG="${2:?--slug needs a value}"; shift 2 ;;
        --all)         EXTRACT_ALL=1; shift ;;
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
[[ "$DELAY" =~ ^[0-9]+$ ]] || die "--delay must be a whole number of seconds"
if [[ "$OFFLINE" -eq 0 && "$ALLOW_FAST" -eq 0 && "$DELAY" -lt 10 ]]; then
    log "error: --delay must be at least 10s for live runs; --allow-fast is for fixtures only"
    exit 2
fi
if [[ -n "$SNAPSHOT_DIR" && "$OFFLINE" -eq 0 ]]; then
    log "error: --snapshot is for reading; a live run always creates its own snapshot"
    exit 2
fi
have jq || die "jq is required"

if [[ -n "$PROBE_JSON" && "$PROBE" -eq 0 ]]; then
    log "error: --probe-json needs --probe"
    exit 2
fi

if [[ "$PROBE" -eq 1 ]]; then
    if [[ -n "$OUT" ]]; then
        log "error: --probe cannot be combined with --out"
        exit 2
    fi
    if [[ -n "$SEARCH" ]]; then
        log "error: --probe cannot be combined with --search"
        exit 2
    fi
    if [[ -n "$SINCE" && "$SINCE_LAST" -eq 1 ]]; then
        log "error: --since and --since-last are mutually exclusive"
        exit 2
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '%s\n' "$(probe_url)"
        exit 0
    fi
    probe_kb
    exit 0
fi

if [[ "$SINCE_LAST" -eq 1 ]]; then
    if [[ "$SOURCE" != "api" ]]; then
        log "error: --since-last needs --source api"
        exit 2
    fi
    if [[ -n "$SINCE" ]]; then
        log "error: --since and --since-last are mutually exclusive"
        exit 2
    fi
    SINCE="$(cursor_fetched_at)"
    log "using modified_after=$SINCE from the last run"
fi

if [[ -n "$SEARCH_JSON" && -z "$SEARCH" ]]; then
    log "error: --search-json needs --search"
    exit 2
fi

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
    if [[ "$DRY_RUN" -eq 1 ]]; then
        search_url
        exit 0
    fi
    search_kb
    exit 0
fi

if [[ "$JSON_OUT" -eq 1 ]]; then
    log "error: --json needs --search"
    exit 2
fi

if [[ -n "$SLUG" || "$EXTRACT_ALL" -eq 1 ]]; then
    case "$FORMAT" in
        ""|text|markdown) ;;
        *) log "error: --format must be text or markdown"; exit 2 ;;
    esac
    FORMAT="${FORMAT:-markdown}"
    if [[ -n "$SLUG" && "$EXTRACT_ALL" -eq 1 ]]; then
        log "error: use --slug or --all, not both"
        exit 2
    fi
    if [[ -n "$OUT" ]]; then
        log "error: --slug/--all write into the cache; do not combine with --out"
        exit 2
    fi
    if [[ "$FORMAT" == "markdown" ]] && ! have pandoc; then
        log "warning: pandoc not found; using the built-in converter"
    fi
    extract_slugs
    exit 0
fi

if [[ -n "$FORMAT" ]]; then
    log "error: --format needs --slug or --all"
    exit 2
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ "$SOURCE" == "api" ]]; then
        printf '%s\n' "$(api_url 1)"
    else
        printf '%s\n' "$SITEMAP"
    fi
    exit 0
fi

mkdir -p "$CACHE"
FETCHED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# One live run at a time: two interleaved runs would fight over snapshot names.
if [[ "$OFFLINE" -eq 0 ]] && have flock; then
    exec 9>"$CACHE/.lock"
    if ! flock -n 9; then
        die "another run holds $CACHE/.lock"
    fi
fi

if [[ "$OFFLINE" -eq 1 ]]; then
    RUN_DIR="$(read_dir)"
    log "reading snapshot: $RUN_DIR"
else
    RUN_DIR="$(new_snapshot_dir)"
fi

ENTRIES="$(mktemp)"
ENTARRAY="$(mktemp)"
CATTMP="$(mktemp)"
CATMAP="$(mktemp)"
TMPAGE="$(mktemp)"
trap 'rm -f "$ENTRIES" "$ENTARRAY" "$CATTMP" "$CATMAP" "$TMPAGE" "$CACHE"/*.tmp' EXIT

# --- api source -------------------------------------------------------------

api_page_file() {
    if [[ -n "$SINCE" ]]; then
        printf '%s/api-since-%s-page-%s.json' "$RUN_DIR" "$(slugify "$SINCE")" "$1"
    else
        printf '%s/api-page-%s.json' "$RUN_DIR" "$1"
    fi
}

api_cat_file() { printf '%s/api-kbcategories-%s.json' "$RUN_DIR" "$1"; }

# Load one API page into PAGE_JSON. Returns 1 when the page cannot be read.
fetch_api_page() {
    local page="$1" file url hdr total pages size
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

    size="$(wc -c < "$file.tmp" | tr -d ' ')"
    if [[ "$size" -gt $((8 * 1024 * 1024)) ]]; then
        rm -f "$file.tmp"
        die "response too large for $url ($size bytes)"
    fi
    if ! jq -e 'type == "array"' "$file.tmp" >/dev/null 2>&1; then
        rm -f "$file.tmp"
        die "response is not a JSON array: $url"
    fi
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
                modified: (.modified_gmt // ""),
                published: (.date_gmt // ""),
                categories: ((.kbcategories // [])
                    | map($cm[(tostring)] // ("term-" + (tostring)))),
                source: "api",
                text: (.content.rendered // "")
              }' <<<"$PAGE_JSON" > "$TMPAGE"

        while IFS= read -r rec; do
            [[ -n "$rec" ]] || continue
            sha="$(jq -jr '.text' <<<"$rec" | sha256sum | cut -d' ' -f1)"
            title="$(jq -r '.title' <<<"$rec" | decode_entities)"
            jq -c --arg sha "$sha" --arg title "$title" --arg fetched "$FETCHED" '
                del(.text)
                | .title = $title
                | .sha256 = $sha
                | .fetched_at = $fetched' <<<"$rec" >> "$ENTRIES"
        done < "$TMPAGE"

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
        htmlfile="$RUN_DIR/$slug.html"

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
            printf '%s' "$html" | pandoc -f html -t gfm -o "$RUN_DIR/$slug.md" 2>/dev/null || true
        fi

        printf '{"url":"%s","title":"%s","lastmod":"%s","modified":"","published":"","categories":[],"source":"sitemap","fetched_at":"%s","sha256":"%s"}\n' \
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
    if [[ "$PARTIAL" -eq 1 ]]; then
        log "warning: manifest has $count entries but the API reported X-WP-Total: $WP_TOTAL (--partial)"
    else
        die "manifest has $count entries but the API reported X-WP-Total: $WP_TOTAL (use --partial to accept a partial dataset)"
    fi
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
        '{schema: 2, source: $source}
         + (if $source == "api" then {base: $base} else {} end)
         + (if $since != "" then {since: $since} else {} end)
         + {fetched_at: $fetched, count: $total, entries: $e[0]}'
}

if [[ "$OFFLINE" -eq 0 ]]; then
    if ! guard_count_drop; then
        exit 1
    fi
    emit_manifest > "$RUN_DIR/manifest.json"
    update_latest
    log "wrote $count entries to $RUN_DIR/manifest.json"
fi

if [[ -n "$OUT" ]]; then
    emit_manifest > "$OUT"
    log "wrote $count entries to $OUT"
elif [[ "$OFFLINE" -eq 1 ]]; then
    emit_manifest
    log "wrote $count entries to stdout"
fi

# Advance the cursor only on a complete live api run: a --limit or --since run
# is partial and must not make --since-last skip posts.
if [[ "$SOURCE" == "api" && "$OFFLINE" -eq 0 && "$LIMIT" -eq 0 && -z "$SINCE" ]]; then
    write_cursor
fi
