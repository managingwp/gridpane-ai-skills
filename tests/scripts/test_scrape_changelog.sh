#!/usr/bin/env bash
#
# test_scrape_changelog.sh - offline test for
# gridpane-tooling/scripts/scrape-changelog.sh.
#
# Feeds a fixture changelog page via --changelog-json and checks the digest
# fields, deduplication, ordering and --help. Never touches the network.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRAPER="$REPO_ROOT/skills/gridpane-tooling/scripts/scrape-changelog.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ok() { printf 'ok: %s\n' "$1"; }

[[ -x "$SCRAPER" ]] || fail "scraper not executable: $SCRAPER"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/page.json" <<'JSON'
{
  "items": [
    {"id": "aaa", "title": "Older entry", "content": "<p>x</p>", "publishedAt": "2026-01-01T00:00:00.000+00:00", "tags": [{"label": "Fixed"}]},
    {"id": "bbb", "title": "Newer entry", "content": "<p>y</p>", "publishedAt": "2026-05-01T00:00:00.000+00:00", "tags": []},
    {"id": "aaa", "title": "Older entry (dup)", "content": "<p>z</p>", "publishedAt": "2026-01-01T00:00:00.000+00:00", "tags": [{"label": "Fixed"}]}
  ],
  "total": 3,
  "perPage": 100,
  "page": 1,
  "pages": 1
}
JSON

"$SCRAPER" --changelog-json "$WORK/page.json" --out "$WORK/manifest.json" 2>"$WORK/stderr"
M="$WORK/manifest.json"
[[ -s "$M" ]] || fail "manifest is empty"

for field in '"source"' '"fetched_at"' '"count"' '"entries"' '"id"' '"title"' '"published_at"' '"tags"'; do
    grep -q "$field" "$M" || fail "manifest missing $field"
done
ok "manifest has the expected fields"

count="$(jq '.count' "$M")"
[[ "$count" -eq 2 ]] || fail "expected 2 entries after dedupe, got $count"
ok "dedupe by id works (3 -> 2)"

first="$(jq -r '.entries[0].id' "$M")"
[[ "$first" == "bbb" ]] || fail "entries not sorted newest first (got $first)"
ok "entries sorted newest first"

# The duplicate should keep the first occurrence's title.
dup_title="$(jq -r '.entries[] | select(.id=="aaa") | .title' "$M")"
[[ "$dup_title" == "Older entry" ]] || fail "dedupe kept the wrong occurrence: $dup_title"
ok "dedupe keeps the first occurrence"

# An entry with no tags should serialize tags as [].
notags="$(jq -c '.entries[] | select(.id=="bbb") | .tags' "$M")"
[[ "$notags" == "[]" ]] || fail "empty tags should be [], got $notags"
ok "empty tags serialize as []"

"$SCRAPER" --help >/dev/null || fail "--help did not exit 0"
ok "--help exits 0"

printf 'All scrape-changelog tests passed.\n'
