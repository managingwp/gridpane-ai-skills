#!/usr/bin/env bash
#
# test_kb_weekly.sh - offline test for scripts/gridpane-kb-weekly.sh.
#
# Exercises the report-only weekly runner against fixture manifests: the dry-run
# decision, first-run seeding, cited and uncited changes, a timestamp-only edit,
# scrape and delivery failures, lock contention, report building, baseline
# advancement, and the public-repository redaction rule. A fixture "scraper"
# writes the snapshot, so no request leaves the machine and no mail is sent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUNNER="$REPO_ROOT/scripts/gridpane-kb-weekly.sh"

usage() {
    cat <<EOF
Usage: bash tests/scripts/test_kb_weekly.sh

Offline test for 'gridpane-kb-weekly.sh'. Exits 0 when every case passes, 1 on
the first failure, 2 on a bad argument. Touches no network and sends no mail.
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "") : ;;
    *) printf 'error: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
esac

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ok() { printf 'ok: %s\n' "$1"; }

[[ -x "$RUNNER" ]] || fail "not executable: $RUNNER"
command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v flock >/dev/null 2>&1 || fail "flock is required"
have_shellcheck=0
command -v shellcheck >/dev/null 2>&1 && have_shellcheck=1

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
before_status="$(git -C "$REPO_ROOT" status --porcelain)"

STATE="$WORK/state"
CACHE="$WORK/cache"
SENT="$WORK/sent"
SCRAPER_CALLS="$WORK/scraper-calls"

# A URL the repository's own skills cite, so the cited-change path is real. It is
# taken from a prose list item, because the citation map ignores fenced examples.
CITED_URL="$(grep -rhE '^- .*https://gridpane\.com/kb/' "$REPO_ROOT/skills" --include='*.md' \
    | grep -oE 'https://gridpane\.com/kb/[A-Za-z0-9._-]+' | sed -n '1p')"
[[ -n "$CITED_URL" ]] || fail "the skills tree cites no KB URL; cannot build the fixture"

# --- fixtures ---------------------------------------------------------------

# Fixture indexer: writes one dated snapshot and records that it ran.
cat > "$WORK/scraper.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cache=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cache) cache="${2:?}"; shift 2 ;;
        *) shift ;;
    esac
done
[[ -n "$cache" ]] || { printf 'no --cache\n' >&2; exit 2; }
printf '%s\n' "$FIXTURE_MANIFEST" >> "$FIXTURE_CALLS"
mkdir -p "$cache/2026-01-02"
cp "$FIXTURE_MANIFEST" "$cache/2026-01-02/manifest.json"
printf '2026-01-02\n' > "$cache/latest"
SH
chmod +x "$WORK/scraper.sh"

cat > "$WORK/scraper-fail.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'fixture index failure\n' >&2
exit 7
SH
chmod +x "$WORK/scraper-fail.sh"

# Fixture transport: records the subject and body where a real send would land.
cat > "$WORK/email.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
subject="${1:?subject}"
printf '%s\n' "$subject" >> "$FIXTURE_SENT/subjects"
cat >> "$FIXTURE_SENT/body"
printf '%s\n' '---' >> "$FIXTURE_SENT/body"
exit "${FIXTURE_EMAIL_EXIT:-0}"
SH
chmod +x "$WORK/email.sh"

# make_manifest FILE FETCHED SHA TITLE [uncited-new]
make_manifest() {
    local file="$1" fetched="$2" sha="$3" title="$4" extra="${5:-no}"
    jq -n --arg fetched "$fetched" --arg url "$CITED_URL" --arg sha "$sha" \
        --arg title "$title" --arg extra "$extra" '
        {schema: 2, source: "fixture", fetched_at: $fetched, entries: (
            [{url: ($url + "/"), sha256: $sha, title: $title, modified: $fetched}]
            + (if $extra == "yes" then
                 [{url: "https://gridpane.com/kb/fixture-uncited-new/",
                   sha256: "fixture-new", title: "Fixture uncited article",
                   modified: $fetched}]
               else [] end))}
        | .count = (.entries | length)' > "$file"
}

BASE="$WORK/base.json"      # what the previous run acknowledged
CHANGED="$WORK/changed.json" # body change + one added article
SAME="$WORK/same.json"      # identical content, newer timestamp
make_manifest "$BASE" 2026-01-01T00:00:00Z "sha-original" "Fixture article" no
make_manifest "$CHANGED" 2026-01-02T00:00:00Z "sha-new" "Fixture article" yes
make_manifest "$SAME" 2026-01-02T00:00:00Z "sha-original" "Fixture article" no

SEEDED_BASELINE="$WORK/seeded.json"
cp "$BASE" "$SEEDED_BASELINE"

reset() {
    rm -rf "$STATE" "$CACHE" "$SENT"
    mkdir -p "$SENT"
    : > "$SCRAPER_CALLS"
}

# run_weekly MANIFEST [runner args...] -> sets RUN_STATUS, RUN_OUT, RUN_ERR
run_weekly() {
    local manifest="$1"
    shift
    RUN_OUT=""
    RUN_ERR=""
    if RUN_OUT="$(FIXTURE_MANIFEST="$manifest" FIXTURE_CALLS="$SCRAPER_CALLS" \
            FIXTURE_SENT="$SENT" FIXTURE_EMAIL_EXIT="${FIXTURE_EMAIL_EXIT:-0}" \
            "$RUNNER" --state "$STATE" --cache "$CACHE" \
            --scraper "$WORK/scraper.sh" --seed-manifest "$SEEDED_BASELINE" \
            --email-script "$WORK/email.sh" "$@" 2>"$WORK/stderr")"; then
        RUN_STATUS=0
    else
        RUN_STATUS=$?
    fi
    RUN_ERR="$(cat "$WORK/stderr")"
}

mail_count() { [[ -f "$SENT/subjects" ]] && wc -l < "$SENT/subjects" | tr -d ' ' || printf '0'; }

# --- --help and the dry run -------------------------------------------------

out_help="$("$RUNNER" --help 2>&1)" || fail "--help exited non-zero"
grep -q -- '--dry-run' <<<"$out_help" || fail "--help does not document --dry-run"
ok "--help exits 0 and documents the decision flag"

reset
run_weekly "$CHANGED" --dry-run --json
[[ "$RUN_STATUS" -eq 0 ]] || fail "the dry run exited $RUN_STATUS: $RUN_ERR"
jq -e '.decision == "first-run" and .dry_run == true' <<<"$RUN_OUT" >/dev/null \
    || fail "the dry run decision is wrong: $RUN_OUT"
[[ ! -d "$STATE" && ! -d "$CACHE" ]] || fail "the dry run created its state or cache"
[[ ! -s "$SCRAPER_CALLS" ]] || fail "the dry run invoked the indexer"
[[ "$(mail_count)" -eq 0 ]] || fail "the dry run sent mail"
ok "the dry run decides without network, lock, writes or mail"

# --- first run: seeded baseline, cited and uncited changes ------------------

reset
run_weekly "$CHANGED" --json
[[ "$RUN_STATUS" -eq 0 ]] || fail "the first run exited $RUN_STATUS: $RUN_ERR"
jq -e '.result == "sent" and .changed == 2' <<<"$RUN_OUT" >/dev/null \
    || fail "the first run summary is wrong: $RUN_OUT"
[[ "$(mail_count)" -eq 1 ]] || fail "the first run sent $(mail_count) mails, expected 1"
grep -q '2 article(s) need review' "$SENT/subjects" \
    || fail "the subject does not name the change count: $(cat "$SENT/subjects")"
ok "the first run seeds the baseline and sends one summary"

body="$(cat "$SENT/body")"
citation_tmp="$WORK/citation"
grep -rn "$CITED_URL" "$REPO_ROOT/skills" --include='*.md' > "$citation_tmp"
citation="$(sed -n '1p' "$citation_tmp" | cut -d: -f1,2 | sed "s#^$REPO_ROOT/##")"
grep -qF "$citation" <<<"$body" \
    || fail "the report does not name the citing $citation"
grep -q 'Review candidates' <<<"$body" || fail "the report has no review section"
grep -q 'fixture-uncited-new' <<<"$body" \
    || fail "the report does not list the uncited article"
grep -q 'Not cited by any skill' <<<"$body" || fail "the report has no uncited section"
grep -q '1 added, 0 removed, 1 changed, 0 title-only' <<<"$body" \
    || fail "the report's change summary is wrong: $(grep '^Changes:' <<<"$body")"
grep -q 'changed.*rendered body hash' <<<"$body" \
    || fail "the report does not caveat body-hash changes"
ok "the report names the citing file:line, the uncited article and the caveat"

cmp -s "$STATE/baseline-manifest.json" "$CHANGED" \
    || fail "a delivered report did not advance the baseline"
jq -e '.status == "sent" and .email == "ok"' "$STATE/last-run.json" >/dev/null \
    || fail "last-run.json does not record the delivered run"
ok "a delivered report advances the baseline and records the run"

jq -s -e 'length == 1
    and .[0].schema == 1
    and .[0].result == "sent"
    and .[0].snapshot == "2026-01-02"
    and .[0].baseline == "2026-01-01"
    and .[0].counts.added == 1
    and .[0].counts.changed == 1
    and ([.[0].articles[] | select((.citations | length) > 0)] | length) == 1
    and ([.[0].articles[] | select(.title == "Fixture article")] | length) >= 1' \
    "$STATE/history.jsonl" >/dev/null \
    || fail "the ledger record is wrong: $(cat "$STATE/history.jsonl")"
ok "a delivered run appends one history record with articles and citations"

# --- timestamp-only edit ----------------------------------------------------

reset
cp "$BASE" "$STATE/baseline-manifest.json" 2>/dev/null || {
    mkdir -p "$STATE"
    cp "$BASE" "$STATE/baseline-manifest.json"
}
run_weekly "$SAME"
[[ "$RUN_STATUS" -eq 0 ]] || fail "a timestamp-only run exited $RUN_STATUS: $RUN_ERR"
[[ "$(mail_count)" -eq 0 ]] || fail "a timestamp-only edit sent mail"
cmp -s "$STATE/baseline-manifest.json" "$SAME" \
    || fail "a no-change run did not advance the baseline"
ok "a timestamp-only edit reports nothing and still advances the baseline"

# --- no changes at all ------------------------------------------------------

reset
mkdir -p "$STATE"
cp "$BASE" "$STATE/baseline-manifest.json"
run_weekly "$BASE"
[[ "$RUN_STATUS" -eq 0 ]] || fail "an unchanged run exited $RUN_STATUS: $RUN_ERR"
[[ "$(mail_count)" -eq 0 ]] || fail "an unchanged run sent mail"
grep -q 'no-change' "$STATE/last-run.json" \
    || fail "an unchanged run did not record no-change"
ok "an unchanged KB stays silent"

# --- scrape failure ---------------------------------------------------------

reset
mkdir -p "$STATE"
cp "$BASE" "$STATE/baseline-manifest.json"
if FIXTURE_SENT="$SENT" "$RUNNER" --state "$STATE" --cache "$CACHE" \
        --scraper "$WORK/scraper-fail.sh" --seed-manifest "$SEEDED_BASELINE" \
        --email-script "$WORK/email.sh" >"$WORK/out" 2>"$WORK/err"; then
    fail "a failing indexer exited 0"
else
    RUN_STATUS=$?
fi
[[ "$RUN_STATUS" -eq 1 ]] || fail "a failing indexer exited $RUN_STATUS, expected 1"
grep -q 'FAILED' "$SENT/subjects" || fail "a scrape failure sent no failure mail"
cmp -s "$STATE/baseline-manifest.json" "$BASE" \
    || fail "a scrape failure advanced the baseline"
ok "a scrape failure sends a failure mail and keeps the baseline"

# --- malformed index output -------------------------------------------------

reset
mkdir -p "$STATE"
cp "$BASE" "$STATE/baseline-manifest.json"
printf 'not json\n' > "$WORK/broken.json"
run_weekly "$WORK/broken.json"
[[ "$RUN_STATUS" -eq 1 ]] || fail "a malformed manifest exited $RUN_STATUS: $RUN_ERR"
cmp -s "$STATE/baseline-manifest.json" "$BASE" \
    || fail "a malformed manifest advanced the baseline"
ok "a malformed index result fails instead of reporting nothing"

# --- delivery failure -------------------------------------------------------

reset
mkdir -p "$STATE"
cp "$BASE" "$STATE/baseline-manifest.json"
FIXTURE_EMAIL_EXIT=1 run_weekly "$CHANGED"
[[ "$RUN_STATUS" -eq 1 ]] || fail "a failed send exited $RUN_STATUS: $RUN_ERR"
cmp -s "$STATE/baseline-manifest.json" "$BASE" \
    || fail "a failed send advanced the baseline"
jq -e '.status == "delivery-failed"' "$STATE/last-run.json" >/dev/null \
    || fail "a failed send was not recorded as delivery-failed"
[[ -s "$STATE/last-report.txt" ]] || fail "a failed send kept no report"
jq -s -e 'length == 1 and .[0].result == "delivery-failed"' \
    "$STATE/history.jsonl" >/dev/null \
    || fail "a failed send wrote no failed ledger record"
ok "a failed send keeps the report and the baseline for the next run"

# --- held report ------------------------------------------------------------

reset
mkdir -p "$STATE"
cp "$BASE" "$STATE/baseline-manifest.json"
run_weekly "$CHANGED" --no-email
[[ "$RUN_STATUS" -eq 3 ]] || fail "--no-email exited $RUN_STATUS, expected 3"
[[ "$(mail_count)" -eq 0 ]] || fail "--no-email sent mail"
cmp -s "$STATE/baseline-manifest.json" "$BASE" \
    || fail "--no-email advanced the baseline"
[[ -s "$STATE/last-report.txt" ]] || fail "--no-email stored no report"
jq -s -e 'length == 1 and .[0].result == "held"' \
    "$STATE/history.jsonl" >/dev/null \
    || fail "--no-email wrote no held ledger record"
ok "--no-email stores the report, sends nothing and exits 3"

# --- lock contention --------------------------------------------------------

reset
mkdir -p "$STATE"
(
    exec 9>"$STATE/run.lock"
    flock -n 9 || exit 1
    sleep 3
) &
holder=$!
sleep 0.5
run_weekly "$CHANGED"
[[ "$RUN_STATUS" -eq 2 ]] || fail "a held lock exited $RUN_STATUS, expected 2"
grep -q 'already running' <<<"$RUN_ERR" \
    || fail "a held lock did not explain itself: $RUN_ERR"
[[ ! -s "$SCRAPER_CALLS" ]] || fail "a held lock still ran the indexer"
wait "$holder" 2>/dev/null || true
ok "a concurrent run is refused before any request"

# --- no recipient surface ---------------------------------------------------

reset
if "$RUNNER" --state "$STATE" --cache "$CACHE" operator@example.com \
        >"$WORK/out" 2>"$WORK/err"; then
    fail "a positional recipient argument was accepted"
fi
grep -q 'no recipient option' "$WORK/err" \
    || fail "a positional argument did not explain the missing recipient option"
if "$RUNNER" --to operator@example.com >"$WORK/out" 2>"$WORK/err"; then
    fail "--to was accepted"
fi
ok "the runner has no recipient argument"

# --- public-repository redaction rule ---------------------------------------

REDACTION_FILES=(
    "$REPO_ROOT/scripts/gridpane-kb-weekly.sh"
    "$REPO_ROOT/scripts/install-kb-weekly-timer.sh"
    "$REPO_ROOT/templates/systemd/gridpane-kb-weekly.service.in"
    "$REPO_ROOT/templates/systemd/gridpane-kb-weekly.timer.in"
)
for f in "${REDACTION_FILES[@]}"; do
    [[ -f "$f" ]] || continue
    if grep -nE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f"; then
        fail "mail address in a tracked file: $f"
    fi
    if grep -nE '/home/|/Users/' "$f"; then
        fail "workstation path in a tracked file: $f"
    fi
done
ok "no address or workstation path reaches a tracked scheduling file"

# --- the checkout is untouched ---------------------------------------------

after_status="$(git -C "$REPO_ROOT" status --porcelain)"
[[ "$before_status" == "$after_status" ]] \
    || fail "the runner or the test modified the checkout"
ok "a full run writes nothing into the checkout"

# --- shellcheck -------------------------------------------------------------

if [[ "$have_shellcheck" -eq 1 ]]; then
    shellcheck -x "$RUNNER" || fail "shellcheck failed on the runner"
    ok "shellcheck passes on the runner"
fi

printf 'all cases passed\n'
