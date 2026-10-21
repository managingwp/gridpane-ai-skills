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
SERVER_PID=""
cleanup() {
    [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

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
   "modified_gmt": "2026-01-02T07:04:05", "date_gmt": "2026-01-01T20:00:00",
   "kbcategories": [10, 11],
   "title": {"rendered": "Example One"},
   "content": {"rendered": "<style>.tbl { font-size: 12px; }</style><h2>Intro</h2><p>Run <code>sitemap-warm-crawl --concurrency 2</code>.</p>"}},
  {"slug": "example-two", "link": "https://gridpane.com/kb/example-two/",
   "modified_gmt": "2026-02-03T08:05:06", "date_gmt": "2026-02-02T21:00:00",
   "kbcategories": [10],
   "title": {"rendered": "Example Two &#038; Friends"},
   "content": {"rendered": "<p>Second body.</p>"}}
]
JSON

cat > "$WORK/cache/api-kbcategories-1.json" <<'JSON'
[{"id": 10, "name": "Server Management"}, {"id": 11, "name": "Caching"}]
JSON

"$SCRAPER" --source api --offline --cache "$WORK/cache" --out "$WORK/api.json" 2>/dev/null

jq -e '.schema == 2 and .source == "api" and .count == 2 and .base == "https://gridpane.com"' "$WORK/api.json" >/dev/null \
    || fail "api manifest envelope is wrong"
jq -e '.entries[0] | .categories == ["Server Management", "Caching"]' "$WORK/api.json" >/dev/null \
    || fail "category names were not resolved"
jq -e '.entries | all(.modified != "" and .published != "" and .sha256 != "" and (has("text") | not))' "$WORK/api.json" >/dev/null \
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
   "modified_gmt": "2025-01-01T04:00:00", "kbcategories": [10],
   "title": {"rendered": "Older Hit"}},
  {"slug": "newer-hit", "link": "https://gridpane.com/kb/newer-hit/",
   "modified_gmt": "2026-03-01T04:00:00", "kbcategories": [10],
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

# --- probe, diff and the delay floor (no network) ---------------------------

cat > "$WORK/probe.json" <<'JSON'
[{"slug": "probe-hit", "modified_gmt": "2026-03-01T04:00:00"}]
JSON

[[ "$("$SCRAPER" --probe --probe-json "$WORK/probe.json" 2>/dev/null)" \
    == $'2026-03-01T04:00:00\tprobe-hit' ]] || fail "probe did not print modified_gmt and slug"
ok "--probe prints modified_gmt and slug from a fixture"

mkdir -p "$WORK/probe-cache"
printf '{"fetched_at":"2027-01-01T00:00:00Z"}\n' > "$WORK/probe-cache/last-run.json"
out="$("$SCRAPER" --probe --since-last --probe-json "$WORK/probe.json" \
    --cache "$WORK/probe-cache" 2>/dev/null)"
[[ "$out" == "no changes since 2027-01-01T00:00:00Z" ]] \
    || fail "probe --since-last did not report 'no changes'"
printf '{"fetched_at":"2026-01-01T00:00:00Z"}\n' > "$WORK/probe-cache/last-run.json"
out="$("$SCRAPER" --probe --since-last --probe-json "$WORK/probe.json" \
    --cache "$WORK/probe-cache" 2>/dev/null)"
[[ "$out" == *"2026-03-01T04:00:00"* ]] || fail "probe --since-last missed the newer post"
ok "probe --since-last compares against the cursor"

if "$SCRAPER" --cache "$WORK/cache" --delay 1 >/dev/null 2>"$WORK/delay.err"; then
    fail "a live run accepted --delay 1"
fi
grep -q 'at least 10s' "$WORK/delay.err" || fail "delay floor message missing"
ok "live runs refuse a delay below 10s"

mkdir -p "$WORK/diff/2026-01-01" "$WORK/diff/2026-01-02"
cat > "$WORK/diff/2026-01-01/manifest.json" <<'JSON'
{"schema":2,"source":"api","count":3,"entries":[
 {"url":"https://gridpane.com/kb/a/","title":"A","modified":"2026-01-01T00:00:00","sha256":"aaa1"},
 {"url":"https://gridpane.com/kb/b/","title":"B old","modified":"2026-01-01T00:00:00","sha256":"bbb1"},
 {"url":"https://gridpane.com/kb/c/","title":"C","modified":"2026-01-01T00:00:00","sha256":"ccc1"}]}
JSON
cat > "$WORK/diff/2026-01-02/manifest.json" <<'JSON'
{"schema":2,"source":"api","count":3,"entries":[
 {"url":"https://gridpane.com/kb/a/","title":"A","modified":"2026-01-02T00:00:00","sha256":"aaa2"},
 {"url":"https://gridpane.com/kb/b/","title":"B new","modified":"2026-01-01T00:00:00","sha256":"bbb1"},
 {"url":"https://gridpane.com/kb/d/","title":"D","modified":"2026-01-02T00:00:00","sha256":"ddd1"}]}
JSON

rows="$("$SCRAPER" --diff --cache "$WORK/diff" 2>"$WORK/diff.err")"
[[ "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" -eq 4 ]] || fail "expected 4 diff rows"
grep -q $'^added\thttps://gridpane.com/kb/d/' <<<"$rows" || fail "added row missing"
grep -q $'^removed\thttps://gridpane.com/kb/c/' <<<"$rows" || fail "removed row missing"
grep -q $'^changed\thttps://gridpane.com/kb/a/' <<<"$rows" || fail "changed row missing"
grep -q $'^title\thttps://gridpane.com/kb/b/' <<<"$rows" || fail "title row missing"
grep -q '1 added, 1 removed, 1 changed, 1 title-only' "$WORK/diff.err" || fail "diff summary missing"
ok "diff classifies added, removed, changed and title-only"

jq -e '.counts == {added:1,removed:1,changed:1,title_changed:1}' \
    <("$SCRAPER" --diff --cache "$WORK/diff" --json 2>/dev/null) >/dev/null \
    || fail "diff --json counts are wrong"

mkdir -p "$WORK/diff/2026-01-03"
cp "$WORK/diff/2026-01-02/manifest.json" "$WORK/diff/2026-01-03/manifest.json"
rows="$("$SCRAPER" --diff --cache "$WORK/diff" 2>"$WORK/diff2.err")"
[[ -z "$rows" ]] || fail "identical snapshots produced rows"
grep -q '0 added, 0 removed, 0 changed, 0 title-only' "$WORK/diff2.err" \
    || fail "zero summary missing"
ok "identical snapshots produce no rows and a zero summary"

mkdir -p "$WORK/one/2026-01-01"
cp "$WORK/diff/2026-01-01/manifest.json" "$WORK/one/2026-01-01/manifest.json"
out="$("$SCRAPER" --diff --cache "$WORK/one" 2>&1)" || fail "single-snapshot diff failed"
grep -q 'only one snapshot' <<<"$out" || fail "single-snapshot diff did not explain itself"

"$SCRAPER" --diff --cache "$WORK/diff" --out "$WORK/nope.json" >/dev/null 2>&1 \
    && fail "--diff --out should exit 2"
ok "single-snapshot diff explains itself and --diff rejects --out"

# --- live snapshots and guards against a loopback fixture server ------------

mkdir -p "$WORK/srv/wp-json/wp/v2"
cat > "$WORK/serve.py" <<'PY'
import http.server, os, socketserver, sys

root = sys.argv[1]

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=root, **kwargs)

    def end_headers(self):
        try:
            with open(os.path.join(root, "total.txt")) as fh:
                total = fh.read().strip()
        except OSError:
            total = ""
        if total:
            self.send_header("X-WP-Total", total)
            self.send_header("X-WP-TotalPages", "1")
        super().end_headers()

    def log_message(self, *args):
        pass

socketserver.TCPServer.allow_reuse_address = True
socketserver.TCPServer(("127.0.0.1", int(sys.argv[2])), Handler).serve_forever()
PY
printf '%s\n' '[{"id":10,"name":"Server Management"}]' \
    > "$WORK/srv/wp-json/wp/v2/kbcategories"

PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
python3 "$WORK/serve.py" "$WORK/srv" "$PORT" >/dev/null 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 50); do
    curl -sf --max-time 1 "http://127.0.0.1:$PORT/wp-json/wp/v2/kb" >/dev/null 2>&1 && break
    sleep 0.1
done

write_posts() {
    python3 - "$1" "$WORK/srv/wp-json/wp/v2/kb" <<'PY'
import json, sys
n = int(sys.argv[1])
posts = [{"slug": f"post-{i}", "link": f"https://gridpane.com/kb/post-{i}/",
          "modified_gmt": f"2026-01-{i:02d}T00:00:00",
          "date_gmt": "2026-01-01T00:00:00", "kbcategories": [10],
          "title": {"rendered": f"Post {i}"},
          "content": {"rendered": f"<p>Body {i}</p>"}} for i in range(1, n + 1)]
open(sys.argv[2], "w").write(json.dumps(posts))
PY
}

set_total() { printf '%s' "$1" > "$WORK/srv/total.txt"; }
snapshots() { find "$WORK/live" -maxdepth 1 -type d -name '20*' 2>/dev/null | sort; }
live_run() {
    "$SCRAPER" --base "http://127.0.0.1:$PORT" --cache "$WORK/live" \
        --allow-fast --delay 0 "$@" 2>>"$WORK/live.err"
}

write_posts 2
set_total 2
live_run || fail "first live run failed"
first="$(snapshots | head -1)"
[[ -f "$first/manifest.json" ]] || fail "first snapshot has no manifest"
[[ "$(jq -r '.count' "$first/manifest.json")" -eq 2 ]] || fail "first snapshot count is wrong"
[[ "$(readlink "$WORK/live/latest")" == "$(basename "$first")" ]] || fail "latest pointer is wrong"
first_fetch="$(jq -r '.fetched_at' "$first/manifest.json")"

live_run || fail "second live run failed"
[[ "$(snapshots | wc -l | tr -d ' ')" -eq 2 ]] || fail "second run did not get its own snapshot"
[[ "$(jq -r '.fetched_at' "$first/manifest.json")" == "$first_fetch" ]] \
    || fail "an existing snapshot was overwritten"
ok "live runs create dated snapshots and never overwrite one"

write_posts 10
set_total 10
live_run || fail "10-post live run failed"
write_posts 2
set_total 2
if live_run; then fail "the count guard did not trip"; fi
grep -q 'entry count dropped' "$WORK/live.err" || fail "count guard message missing"
newest="$(snapshots | tail -1)"
[[ -f "$newest/manifest.json" ]] && fail "the aborted run wrote a manifest"
live_run --force || fail "--force did not override the count guard"
[[ -f "$(snapshots | tail -1)/manifest.json" ]] || fail "the --force run wrote no manifest"
ok "the count guard trips and --force overrides it"

write_posts 1
set_total 2
if live_run; then fail "the X-WP-Total mismatch did not fail"; fi
grep -q 'X-WP-Total' "$WORK/live.err" || fail "total mismatch message missing"
live_run --partial || fail "--partial did not accept the mismatch"
ok "an X-WP-Total mismatch is fatal unless --partial"

# --- refresh wrapper --------------------------------------------------------

WRAPPER="$REPO_ROOT/scripts/refresh-kb-docs.sh"
[[ -x "$WRAPPER" ]] || fail "wrapper not executable: $WRAPPER"
"$WRAPPER" --help >/dev/null || fail "wrapper --help did not exit 0"
"$WRAPPER" --bogus >/dev/null 2>&1 && fail "wrapper accepted an unknown option"
"$WRAPPER" --check-only --offline >/dev/null 2>&1 && fail "wrapper allowed --check-only --offline"

printf '{"fetched_at":"2027-01-01T00:00:00Z"}\n' > "$WORK/probe-cache/last-run.json"
"$WRAPPER" --check-only --cache "$WORK/probe-cache" --probe-json "$WORK/probe.json" \
    >/dev/null 2>&1 || fail "wrapper --check-only should exit 0 when unchanged"

printf '{"fetched_at":"2026-01-01T00:00:00Z"}\n' > "$WORK/probe-cache/last-run.json"
"$WRAPPER" --check-only --cache "$WORK/probe-cache" --probe-json "$WORK/probe.json" \
    >/dev/null 2>&1 && fail "wrapper --check-only should exit 3 when changes exist"
ok "the wrapper rejects bad flags and exits 0/3 from --check-only"

printf 'All scrape-docs tests passed.\n'
