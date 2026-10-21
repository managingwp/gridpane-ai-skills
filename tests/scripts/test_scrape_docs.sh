#!/usr/bin/env bash
#
# test_scrape_docs.sh - offline test for gridpane-tooling/scripts/scrape-docs.sh.
#
# Builds fixture sitemap/API caches and runs the scraper --offline, asserting the
# manifest envelope, per-entry fields for both sources, the request URLs it would
# build, one-request search (from a saved response) and text extraction. Never
# touches the network.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRAPER="$REPO_ROOT/skills/gridpane-tooling/scripts/scrape-docs.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ok() { printf 'ok: %s\n' "$1"; }

[[ -x "$SCRAPER" ]] || fail "scraper not executable: $SCRAPER"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/cache"

cat > "$WORK/sitemap.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://gridpane.com/kb/example-one/</loc><lastmod>2026-01-02T03:04:05+00:00</lastmod></url>
  <url><loc>https://gridpane.com/kb/example-two/</loc><lastmod>2026-02-03T04:05:06+00:00</lastmod></url>
  <url><loc>https://gridpane.com/blog/not-a-kb-page/</loc><lastmod>2026-03-04T05:06:07+00:00</lastmod></url>
</urlset>
XML

# Cache file names use the scraper's documented slug.
printf '<html><head><title>Example One</title></head><body>x</body></html>' \
    > "$WORK/cache/gridpane_com_kb_example_one.html"
printf '<html><head><title>Example Two</title></head><body>y</body></html>' \
    > "$WORK/cache/gridpane_com_kb_example_two.html"

"$SCRAPER" --source sitemap --offline --sitemap "$WORK/sitemap.xml" --cache "$WORK/cache" \
    --out "$WORK/manifest.json" 2>"$WORK/stderr"

MANIFEST="$WORK/manifest.json"
[[ -s "$MANIFEST" ]] || fail "manifest is empty"

for field in '"url"' '"title"' '"lastmod"' '"fetched_at"' '"sha256"'; do
    grep -q "$field" "$MANIFEST" || fail "manifest missing field $field"
done
ok "manifest has all required fields"

entries="$(grep -c '"url"' "$MANIFEST")"
[[ "$entries" -eq 2 ]] || fail "expected 2 entries, got $entries"
ok "manifest has 2 entries"

grep -q 'gridpane.com/kb/example-one' "$MANIFEST" || fail "example-one missing"
grep -q 'Example Two' "$MANIFEST" || fail "title extraction failed"
grep -q 'not-a-kb-page' "$MANIFEST" && fail "non-/kb/ URL was included"
ok "kb filtering and titles are correct"

"$SCRAPER" --help >/dev/null || fail "--help did not exit 0"
ok "--help exits 0"

# --- manifest envelope and sitemap entry fields -----------------------------

jq -e '.source == "sitemap" and .count == 2' "$MANIFEST" >/dev/null \
    || fail "sitemap manifest envelope is wrong"
jq -e '.entries | all(.source == "sitemap")' "$MANIFEST" >/dev/null \
    || fail "sitemap entries carry the wrong source"
jq -e '.entries | all(.modified == "" and (.categories | length) == 0)' "$MANIFEST" >/dev/null \
    || fail "sitemap entries gained api-only fields"
ok "manifest envelope and sitemap entry fields"

# --- api source: offline index from a saved page ----------------------------

cat > "$WORK/cache/api-page-1.json" <<'JSON'
[
  {"slug": "example-one", "link": "https://gridpane.com/kb/example-one/",
   "modified": "2026-01-02T03:04:05", "kbcategories": [10, 11],
   "title": {"rendered": "Example One"},
   "content": {"rendered": "<style>.tbl { font-size: 12px; }</style><h2>Intro</h2><p>Run <code>sitemap-warm-crawl --concurrency 2</code>.</p>"}},
  {"slug": "example-two", "link": "https://gridpane.com/kb/example-two/",
   "modified": "2026-02-03T04:05:06", "kbcategories": [10],
   "title": {"rendered": "Example Two &#038; Friends"},
   "content": {"rendered": "<p>Second body.</p>"}}
]
JSON

cat > "$WORK/cache/api-kbcategories-1.json" <<'JSON'
[{"id": 10, "name": "Server Management"}, {"id": 11, "name": "Caching"}]
JSON

"$SCRAPER" --source api --offline --cache "$WORK/cache" --out "$WORK/api.json" 2>/dev/null

jq -e '.source == "api" and .count == 2 and .base == "https://gridpane.com"' "$WORK/api.json" >/dev/null \
    || fail "api manifest envelope is wrong"
jq -e '.entries[0] | .categories == ["Server Management", "Caching"]' "$WORK/api.json" >/dev/null \
    || fail "category names were not resolved"
jq -e '.entries | all(.modified != "" and .sha256 != "" and (has("text") | not))' "$WORK/api.json" >/dev/null \
    || fail "api entry fields are wrong"
[[ "$(jq -r '.entries[1].title' "$WORK/api.json")" == "Example Two & Friends" ]] \
    || fail "api title was not entity-decoded"
ok "api source builds the envelope and per-entry fields offline"

# --- request URLs, without fetching -----------------------------------------

dry="$("$SCRAPER" --dry-run --since 2026-10-01T00:00:00)"
[[ "$dry" == *'/wp-json/wp/v2/kb?'* ]] || fail "dry-run is missing the REST path"
[[ "$dry" == *'modified_after=2026-10-01T00:00:00'* ]] || fail "dry-run is missing modified_after"

srch="$("$SCRAPER" --search 'fastcgi cache' --limit 5 --dry-run)"
[[ "$srch" == *'search=fastcgi%20cache'* ]] || fail "search query was not URL-encoded"
[[ "$srch" == *'per_page=5'* ]] || fail "search URL ignored --limit"
ok "dry-run builds the index and search URLs"

# --- search from a saved response -------------------------------------------

cat > "$WORK/search.json" <<'JSON'
[
  {"slug": "older-hit", "link": "https://gridpane.com/kb/older-hit/",
   "modified": "2025-01-01T00:00:00", "kbcategories": [10],
   "title": {"rendered": "Older Hit"}},
  {"slug": "newer-hit", "link": "https://gridpane.com/kb/newer-hit/",
   "modified": "2026-03-01T00:00:00", "kbcategories": [10],
   "title": {"rendered": "GridPane&#8217;s Newer Hit"}}
]
JSON

hits="$("$SCRAPER" --search cache --search-json "$WORK/search.json")"
[[ "$(printf '%s\n' "$hits" | wc -l | tr -d ' ')" -eq 2 ]] || fail "search returned the wrong hit count"
[[ "$(printf '%s\n' "$hits" | head -1 | cut -f1)" == "newer-hit" ]] || fail "search is not newest first"
printf '%s\n' "$hits" | head -1 | cut -f4 | grep -q 'Newer Hit' || fail "search lost the title"
printf '%s\n' "$hits" | grep -q '&#8217;' && fail "search title was not entity-decoded"
ok "search prints slug, modified, url, title newest first"

printf '[]\n' > "$WORK/empty.json"
"$SCRAPER" --search nothing --search-json "$WORK/empty.json" >"$WORK/empty.out" 2>"$WORK/empty.err"
[[ -s "$WORK/empty.out" ]] && fail "empty search wrote to stdout"
grep -q 'no matches' "$WORK/empty.err" || fail "empty search did not report no matches"

"$SCRAPER" --search x --out "$WORK/x.json" >/dev/null 2>&1 && fail "--search --out should exit 2"
"$SCRAPER" --search-json "$WORK/search.json" >/dev/null 2>&1 && fail "--search-json alone should exit 2"
ok "empty results and bad flag combinations are handled"

# --- extraction -------------------------------------------------------------

"$SCRAPER" --slug example-one --format markdown --cache "$WORK/cache" 2>/dev/null
MD="$WORK/cache/example-one.md"
[[ -s "$MD" ]] || fail "extraction produced no file"
grep -q 'sitemap-warm-crawl' "$MD" || fail "extracted text lost the command"
grep -q -- '--concurrency' "$MD" || fail "extracted text lost the flag"
grep -qE 'font-size' "$MD" && fail "inline CSS leaked into extracted text"
! grep -q '&#' "$MD" || fail "extracted text kept an HTML entity"
ok "extraction drops CSS and keeps command text"

printf 'All scrape-docs tests passed.\n'
