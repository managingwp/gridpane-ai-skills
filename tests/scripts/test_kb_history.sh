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

LEDGER="$WORK/ledger.jsonl"
OUT="$WORK/KB-CHANGES.md"

run_history() {
    local status=0
    HISTORY_OUT=""
    HISTORY_ERR=""
    if HISTORY_OUT="$("$HISTORY" --ledger "$LEDGER" --out "$OUT" "$@" 2>"$WORK/stderr")"; then
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

# --- shellcheck --------------------------------------------------------------

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -x "$HISTORY" || fail "shellcheck reported a problem"
    ok "shellcheck passes"
else
    printf 'skip: shellcheck not installed\n'
fi

printf 'all cases passed\n'
