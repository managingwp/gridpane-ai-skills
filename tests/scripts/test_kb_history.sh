#!/usr/bin/env bash
#
# test_kb_history.sh - offline test for scripts/gridpane-kb-history.sh.
#
# Exercises the ledger-to-Markdown renderer against fixture records and snapshot
# manifests: month and year grouping, newest-first order, the baseline dedupe
# rule, cited and uncited rendering, the backfill and its idempotence, --check
# exit codes, --json, and a missing ledger. Touches no network.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HISTORY="$REPO_ROOT/scripts/gridpane-kb-history.sh"

usage() {
    cat <<EOF
Usage: bash tests/scripts/test_kb_history.sh

Offline test for 'gridpane-kb-history.sh'. Exits 0 when every case passes, 1 on
the first failure, 2 on a bad argument. Touches no network.
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "") : ;;
    *) printf 'error: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
esac

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ok() { printf 'ok: %s\n' "$1"; }

[[ -x "$HISTORY" ]] || fail "not executable: $HISTORY"
command -v jq >/dev/null 2>&1 || fail "jq is required"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
before_status="$(git -C "$REPO_ROOT" status --porcelain)"

LEDGER="$WORK/ledger.jsonl"
OUT="$WORK/KB-CHANGES.md"

run_history() {
    local status=0
    HISTORY_OUT=""
    HISTORY_ERR=""
    # Always render into the work directory: the diff tree defaults to the
    # repository's own kb-changes/, and a test must not write there.
    if HISTORY_OUT="$("$HISTORY" --ledger "$LEDGER" --out "$OUT" \
            --changes-dir "$WORK/changes" "$@" 2>"$WORK/stderr")"; then
        status=0
    else
        status=$?
    fi
    HISTORY_ERR="$(cat "$WORK/stderr")"
    return "$status"
}

write_record() {
    local file="$1" date="$2" snapshot="$3" baseline="$4" result="$5" articles="$6"
    local counts
    counts="$(jq -n --argjson a "$articles" '
        {added: ([$a[] | select(.status == "added")] | length),
         removed: ([$a[] | select(.status == "removed")] | length),
         changed: ([$a[] | select(.status == "changed")] | length),
         title_only: ([$a[] | select(.status == "title")] | length),
         references: 0, files: 0}')"
    jq -c -n --arg date "$date" --arg snapshot "$snapshot" --arg baseline "$baseline" \
        --arg result "$result" --argjson articles "$articles" --argjson counts "$counts" '
        {schema: 1, date: $date, snapshot: $snapshot, baseline: $baseline,
         result: $result, counts: $counts, articles: $articles}' >>"$file"
}

# --- --help ------------------------------------------------------------------

help_out="$("$HISTORY" --help 2>&1)" || fail "--help exited non-zero"
grep -q -- '--backfill' <<<"$help_out" || fail "--help does not document --backfill"
grep -q -- '--check' <<<"$help_out" || fail "--help does not document --check"
ok "--help exits 0 and documents the backfill and check flags"

# --- grouping, order and rendering ------------------------------------------

cat >"$LEDGER" <<'EOF'
{"schema":1,"date":"2026-11-09","snapshot":"2026-11-09","baseline":"2026-11-06","result":"sent","counts":{"added":0,"removed":0,"changed":1,"title_only":0,"references":1,"files":1},"articles":[{"status":"changed","url":"https://gridpane.com/kb/peakfreq-managed-hosting","title":"PeakFreq Managed Hosting","citations":["skills/gridpane-core/references/stack-overview.md:37"]}]}
{"schema":1,"date":"2026-12-01","snapshot":"2026-12-01","baseline":"2026-11-09","result":"no-change","counts":{"added":0,"removed":0,"changed":0,"title_only":0,"references":0,"files":0},"articles":[]}
{"schema":1,"date":"2026-10-21","snapshot":"2026-10-21-3","baseline":"2026-10-01","result":"backfilled","counts":{"added":1,"removed":0,"changed":0,"title_only":0,"references":0,"files":0},"articles":[{"status":"added","url":"https://gridpane.com/kb/new-article","title":"New article","citations":[]}]}
EOF

run_history || fail "the render exited $?: $HISTORY_ERR"
[[ -f "$OUT" ]] || fail "the render wrote no file"
grep -q '^## 2026$' "$OUT" || fail "no year heading: $(grep '^## ' "$OUT")"
grep -q '^### December 2026$' "$OUT" || fail "no December heading"
grep -q '^### November 2026$' "$OUT" || fail "no November heading"
dec_line="$(grep -n '^### December 2026$' "$OUT" | cut -d: -f1)"
nov_line="$(grep -n '^### November 2026$' "$OUT" | cut -d: -f1)"
oct_line="$(grep -n '^### October 2026$' "$OUT" | cut -d: -f1)"
(( dec_line < nov_line && nov_line < oct_line )) \
    || fail "months are not newest first ($dec_line/$nov_line/$oct_line)"
grep -q '| December 2026 | 1 | 0 | 0 | 0 | 0 |' "$OUT" \
    || fail "the month summary row is wrong: $(grep '^| 20' "$OUT")"
grep -q 'cited by `skills/gridpane-core/references/stack-overview.md:37`' "$OUT" \
    || fail "the cited article does not name its citation"
grep -q '^- added — \[New article\]' "$OUT" || fail "the added article is missing"
grep -q 'citations were not recorded' "$OUT" \
    || fail "the backfilled record does not caveat its citations"
grep -q '^- no article changes$' "$OUT" || fail "the no-change run is missing"
ok "renders year and month sections, newest first, with counts and citations"

# --- baseline dedupe ---------------------------------------------------------

: >"$LEDGER"
write_record "$LEDGER" 2026-11-09 2026-11-09 2026-11-06 held \
    '[{"status":"changed","url":"https://gridpane.com/kb/a","title":"A","citations":[]}]'
write_record "$LEDGER" 2026-11-09 2026-11-09 2026-11-06 sent \
    '[{"status":"changed","url":"https://gridpane.com/kb/a","title":"A","citations":[]}]'
run_history || fail "the dedupe render exited $?: $HISTORY_ERR"
[[ "$(grep -c 'snapshot `2026-11-09`' "$OUT")" -eq 1 ]] \
    || fail "the superseded attempt was rendered twice"
grep -q '· sent' "$OUT" || fail "the delivered record did not win"
if grep -q '· held' "$OUT"; then
    fail "the held attempt survived the delivered record"
fi
ok "keeps one record per baseline, preferring the delivered one"

# --- --check -----------------------------------------------------------------

run_history || fail "the check render exited $?: $HISTORY_ERR"
before="$(cksum <"$OUT")"
if run_history --check; then
    :
else
    fail "--check reported a stale file it had just written: $HISTORY_ERR"
fi
grep -q 'current:' <<<"$HISTORY_ERR" || fail "--check did not explain itself"
write_record "$LEDGER" 2026-12-15 2026-12-15 2026-12-01 no-change '[]'
if run_history --check; then
    fail "--check accepted a stale file"
else
    [[ $? -eq 3 ]] || fail "--check exited $?, expected 3"
fi
after="$(cksum <"$OUT")"
[[ "$before" == "$after" ]] || fail "--check modified the file"
ok "--check exits 0 when current and 3 when stale, writing nothing"

# --- --json ------------------------------------------------------------------

run_history --json || fail "the JSON render exited $?: $HISTORY_ERR"
out="$HISTORY_OUT"
jq -e '.records == 2 and (.months | length) == 2' <<<"$out" >/dev/null \
    || fail "the JSON aggregate is wrong: $out"
jq -e '.months[0].reports == 1' <<<"$out" >/dev/null \
    || fail "the JSON month counts are wrong: $out"
jq -e '.months[0].label == "December 2026"' <<<"$out" >/dev/null \
    || fail "the JSON month labels are wrong: $out"
ok "--json prints the record count and month aggregate"

# --- missing ledger ----------------------------------------------------------

if run_history --ledger "$WORK/missing.jsonl"; then
    fail "a missing ledger exited 0"
else
    [[ $? -eq 1 ]] || fail "a missing ledger exited $?, expected 1"
fi
grep -q 'ledger not found' <<<"$HISTORY_ERR" || fail "a missing ledger did not explain itself"
ok "a missing ledger fails with exit 1"

# --- backfill ----------------------------------------------------------------

CACHE="$WORK/cache"
mkdir -p "$CACHE/2026-01-01" "$CACHE/2026-02-01"
jq -n '{fetched_at: "2026-01-01T00:00:00Z", count: 4, entries: [
    {url: "https://gridpane.com/kb/a/", sha256: "sha-a", title: "Alpha"},
    {url: "https://gridpane.com/kb/b/", sha256: "sha-b", title: "Bravo"},
    {url: "https://gridpane.com/kb/d/", sha256: "sha-d", title: "Delta"}]}' \
    >"$CACHE/2026-01-01/manifest.json"
jq -n '{fetched_at: "2026-02-01T00:00:00Z", count: 4, entries: [
    {url: "https://gridpane.com/kb/a/", sha256: "sha-a", title: "Alpha renamed"},
    {url: "https://gridpane.com/kb/b/", sha256: "sha-b2", title: "Bravo"},
    {url: "https://gridpane.com/kb/c/", sha256: "sha-c", title: "Charlie"}]}' \
    >"$CACHE/2026-02-01/manifest.json"

LEDGER="$WORK/backfill.jsonl"
OUT="$WORK/backfill.md"
run_history --cache "$CACHE" --backfill || fail "the backfill exited $?: $HISTORY_ERR"
[[ "$(wc -l <"$LEDGER" | tr -d ' ')" -eq 1 ]] || fail "the backfill wrote $(wc -l <"$LEDGER") records"
jq -s -e '.[0].result == "backfilled" and .[0].baseline == "2026-01-01"
    and .[0].counts.added == 1 and .[0].counts.removed == 1
    and .[0].counts.changed == 1 and .[0].counts.title_only == 1' "$LEDGER" >/dev/null \
    || fail "the backfilled record is wrong: $(cat "$LEDGER")"
grep -q '1 added · 1 removed · 1 changed · 1 title-only' "$OUT" \
    || fail "the backfilled counts are missing from the history"
grep -q '^- removed — \[Delta\]' "$OUT" || fail "the removed article is missing"
grep -q '^- title-only — \[Alpha renamed\]' "$OUT" || fail "the title-only article is missing"
ok "backfill diffs two snapshots into one interval record"

run_history --cache "$CACHE" --backfill || fail "the second backfill exited $?: $HISTORY_ERR"
[[ "$(wc -l <"$LEDGER" | tr -d ' ')" -eq 1 ]] || fail "a repeated backfill duplicated the interval"
ok "a repeated backfill is a no-op"

# --- diff tree ---------------------------------------------------------------

# Two snapshots with real bodies, so the extractor and the differ run offline.
DIFFCACHE="$WORK/diffcache"
STATE2="$WORK/state2"
mkdir -p "$DIFFCACHE/2026-01-01" "$DIFFCACHE/2026-02-01" "$STATE2"

make_page() { # DIR SLUG TITLE BODY
    local dir="$1" slug="$2" title="$3" body="$4" file="$1/api-page-1.json"
    if [[ -f "$file" ]]; then
        jq --arg slug "$slug" --arg title "$title" --arg body "$body" \
            '. + [{slug: $slug, title: {rendered: $title},
                   content: {rendered: $body}, modified_gmt: "2026-01-01T00:00:00"}]' \
            "$file" >"$file.tmp" && mv "$file.tmp" "$file"
    else
        jq -n --arg slug "$slug" --arg title "$title" --arg body "$body" \
            '[{slug: $slug, title: {rendered: $title},
               content: {rendered: $body}, modified_gmt: "2026-01-01T00:00:00"}]' \
            >"$file"
    fi
}

# 1800 short paragraphs (~80 KB), so the diff is larger than the 64 KB cap while
# every argument stays under the 128 KB exec limit.
huge_old="$WORK/huge-old.html"
huge_new="$WORK/huge-new.html"
{
    printf '<p>Introduction line</p>\n'
    seq 1 1800 | while IFS= read -r n; do printf '<p>Paragraph %s of the long article</p>\n' "$n"; done
} >"$huge_old"
# Every paragraph changes, so the diff itself — not just one line — is oversized.
cp "$huge_old" "$huge_new"
sed -i 's/of the long article/of the revised article/' "$huge_new"

old_body='<p>Alpha one</p>'
new_body='<p>Alpha two</p>'
same_body='<p>Bravo stays</p>'
make_page "$DIFFCACHE/2026-01-01" alpha "Alpha" "$old_body"
make_page "$DIFFCACHE/2026-01-01" bravo "Bravo" "$same_body"
make_page "$DIFFCACHE/2026-01-01" delta "Delta" '<p>Delta goes away</p>'
make_page "$DIFFCACHE/2026-01-01" echo-title "Echo" '<p>Echo body</p>'
make_page "$DIFFCACHE/2026-01-01" huge "Huge" "$(cat "$huge_old")"
make_page "$DIFFCACHE/2026-02-01" alpha "Alpha" "$new_body"
make_page "$DIFFCACHE/2026-02-01" bravo "Bravo" '<div class="wrapper"><p>Bravo stays</p></div>'
make_page "$DIFFCACHE/2026-02-01" charlie "Charlie" '<p>Charlie is new</p>'
make_page "$DIFFCACHE/2026-02-01" echo-title "Echo renamed" '<p>Echo body</p>'
make_page "$DIFFCACHE/2026-02-01" huge "Huge" "$(cat "$huge_new")"

# Manifests carry titles only (bodies come from the api pages above).
make_manifest_from_pages() { # DIR FETCHED
    jq --arg fetched "$2" '
        {fetched_at: $fetched, count: length,
         entries: [ .[] | {url: ("https://gridpane.com/kb/" + .slug + "/"),
                            title: .title.rendered, sha256: "fixture"}]}' \
        "$1/api-page-1.json" >"$1/manifest.json"
}

make_manifest_from_pages "$DIFFCACHE/2026-01-01" "2026-01-01T00:00:00Z"
make_manifest_from_pages "$DIFFCACHE/2026-02-01" "2026-02-01T00:00:00Z"

AFFECTED="$WORK/affected.json"
jq -n '{rows: [
    {status: "changed", url: "https://gridpane.com/kb/alpha",
     file: "/tmp/skills/gridpane-core/references/sources.md", line: 12},
    {status: "changed", url: "https://gridpane.com/kb/bravo", file: null, line: null},
    {status: "added", url: "https://gridpane.com/kb/charlie", file: null, line: null},
    {status: "removed", url: "https://gridpane.com/kb/delta", file: null, line: null},
    {status: "title", url: "https://gridpane.com/kb/echo-title", file: null, line: null},
    {status: "changed", url: "https://gridpane.com/kb/huge", file: null, line: null}]}' \
    >"$AFFECTED"

emit() {
    "$HISTORY" --emit-diffs --affected "$AFFECTED" --date 2026-02-01 \
        --snapshot "$DIFFCACHE/2026-02-01" --baseline-snapshot "$DIFFCACHE/2026-01-01" \
        --state "$STATE2" 2>"$WORK/emit.err"
}

if ! emit >"$WORK/emit.tsv"; then
    fail "the diff emission exited $?: $(cat "$WORK/emit.err")"
fi
DIFFS="$STATE2/diffs/2026-02-01"
[[ -d "$DIFFS" ]] || fail "no diff directory was written"
[[ "$(ls "$DIFFS" | wc -l | tr -d ' ')" -eq 6 ]] \
    || fail "expected six diff files, found: $(ls "$DIFFS" | tr '\n' ' ')"
grep -q '^@@' "$DIFFS/2026-02-01-alpha.md" || fail "a text change carries no hunk"
grep -q 'markup only' "$DIFFS/2026-02-01-bravo.md" \
    || fail "an identical body was not reported as markup-only"
grep -q 'New article' "$DIFFS/2026-02-01-charlie.md" || fail "the added stub is missing"
grep -q 'Charlie is new' "$DIFFS/2026-02-01-charlie.md" \
    && fail "the added stub carries the article body"
grep -q 'no longer appears' "$DIFFS/2026-02-01-delta.md" || fail "the removed note is missing"
grep -q 'Echo renamed' "$DIFFS/2026-02-01-echo-title.md" || fail "the title change is missing"
grep -q 'Derived by a workstation path' "$DIFFS/2026-02-01-alpha.md" \
    && fail "a diff carries a workstation path"
grep -q '/tmp/skills' "$DIFFS/2026-02-01-alpha.md" \
    && fail "a diff carries an absolute citation path"
grep -q 'Diff truncated at 64 KB' "$DIFFS/2026-02-01-huge.md" \
    || fail "an oversized diff was not truncated"
huge_bytes="$(wc -c <"$DIFFS/2026-02-01-huge.md" | tr -d ' ')"
[[ "$huge_bytes" -lt 72000 ]] || fail "the truncated diff is $huge_bytes bytes"
ok "the diff tree covers text, markup-only, added, removed, title-only and the cap"

cp -R "$DIFFS" "$WORK/diffs-first"
emit >/dev/null || fail "the second emission exited $?: $(cat "$WORK/emit.err")"
if ! diff -r "$WORK/diffs-first" "$DIFFS" >/dev/null; then
    fail "a second emission produced different bytes"
fi
ok "a rerun with the same snapshots produces identical bytes"

# A record whose snapshots are gone renders without a link rather than inventing
# one.
LEDGER3="$WORK/ledger3.jsonl"
OUT3="$WORK/history3.md"
jq -c -n '{schema: 1, date: "2026-03-01", snapshot: "2099-01-01", baseline: "2099-01-01",
    result: "backfilled", counts: {added: 0, removed: 0, changed: 1, title_only: 0,
    references: 0, files: 0},
    articles: [{status: "changed", url: "https://gridpane.com/kb/gone",
                title: "Gone", citations: []}]}' >"$LEDGER3"
"$HISTORY" --ledger "$LEDGER3" --out "$OUT3" --changes-dir "$WORK/changes3" \
    --state "$STATE2" 2>/dev/null || fail "the gone-snapshot render exited $?"
if grep -q '\[diff\](' "$OUT3"; then
    fail "a record with no snapshots was linked to a diff"
fi
ok "a record with no retained snapshots renders without a link"

# The tree renders, then --check agrees, then notices each kind of drift.
LEDGER2="$WORK/ledger2.jsonl"
OUT2="$WORK/render/KB-CHANGES.md"
CHANGES2="$WORK/render/kb-changes"
jq -c -n --argjson articles "$(jq -c '[.rows | group_by(.url) | .[] | .[0]
    | {status, url, title: "", citations: []}]' "$AFFECTED")" '
    {schema: 2, date: "2026-02-01", snapshot: "2026-02-01", baseline: "2026-01-01",
     baseline_snapshot: "2026-01-01", diff_dir: "diffs/2026-02-01", result: "sent",
     counts: {added: 1, removed: 1, changed: 3, title_only: 1, references: 0, files: 0},
     articles: $articles}' >"$LEDGER2"

render2() {
    "$HISTORY" --ledger "$LEDGER2" --out "$OUT2" --changes-dir "$CHANGES2" \
        --state "$STATE2" "$@" 2>"$WORK/render2.err"
}

render2 || fail "the tree render exited $?: $(cat "$WORK/render2.err")"
[[ -f "$CHANGES2/README.md" ]] || fail "the tree has no README"
[[ -f "$CHANGES2/2026/02/2026-02-01-alpha.md" ]] || fail "the tree is missing a diff"
grep -q '\[diff\](kb-changes/2026/02/2026-02-01-alpha.md)' "$OUT2" \
    || fail "the history does not link the diff: $(cat "$OUT2")"
grep -q 'Cited by: `skills/gridpane-core/references/sources.md:12`' \
    "$CHANGES2/2026/02/2026-02-01-alpha.md" \
    || fail "the diff header lost its checkout-relative citation"
render2 --check || fail "--check rejected a tree it had just written"
ok "the tree renders with links and --check agrees"

printf 'tampered\n' >>"$CHANGES2/2026/02/2026-02-01-alpha.md"
if render2 --check; then fail "--check accepted an edited diff"; else [[ $? -eq 3 ]] || fail "--check exited $?"; fi
printf 'stray\n' >"$CHANGES2/2026/02/2026-02-01-nosuch.md"
if render2 --check; then fail "--check accepted an orphan"; else [[ $? -eq 3 ]] || fail "--check exited $?"; fi
rm -f "$CHANGES2/2026/02/2026-02-01-alpha.md" "$CHANGES2/2026/02/2026-02-01-nosuch.md"
if render2 --check; then fail "--check accepted a missing diff"; else [[ $? -eq 3 ]] || fail "--check exited $?"; fi
ok "--check exits 3 for an edited, an orphaned and a missing file"

render2 || fail "the recovery render exited $?: $(cat "$WORK/render2.err")"
render2 --check || fail "--check did not recover after a re-render"
ok "a re-render restores the tree and --check returns to 0"

# --- shellcheck --------------------------------------------------------------

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -x "$HISTORY" || fail "shellcheck reported a problem"
    ok "shellcheck passes"

after_status="$(git -C "$REPO_ROOT" status --porcelain)"
if [[ "$after_status" != "$before_status" ]]; then
    fail "the suite changed the checkout: $(diff <(printf '%s\n' "$before_status") \
        <(printf '%s\n' "$after_status"))"
fi
ok "the suite writes nothing into the checkout"
else
    printf 'skip: shellcheck not installed\n'
fi

printf 'all cases passed\n'
