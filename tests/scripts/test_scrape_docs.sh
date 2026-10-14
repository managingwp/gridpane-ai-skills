#!/usr/bin/env bash
#
# test_scrape_docs.sh - offline test for gridpane-tooling/scripts/scrape-docs.sh.
#
# Builds a fixture sitemap and cache, runs the scraper with --offline, and checks
# the manifest has the required fields and the expected entry count. Never
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

"$SCRAPER" --offline --sitemap "$WORK/sitemap.xml" --cache "$WORK/cache" \
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

printf 'All scrape-docs tests passed.\n'
