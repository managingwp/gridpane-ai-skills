#!/usr/bin/env bash
#
# gridpane-kb-weekly.sh - report-only weekly check of the GridPane Knowledge Base.
#
# Indexes the public KB into an isolated cache, compares the result with the
# baseline this job last acknowledged, and emails the articles that need a human
# to look at them. It never edits a skill, commits, pushes, releases, publishes
# the committed manifest or prunes a snapshot: a person decides what to do with
# the report, using the gridpane-kb-refresh skill.
#
# The recipient is never an argument. Mail goes through the configured
# send-email transport, so a scheduled run cannot address anyone but the mailbox
# that transport already owns.
#
# Isolation: snapshots, the baseline, the last report and the run metadata live
# under out/gridpane-kb-weekly/, which is gitignored. A scheduled run therefore
# cannot race a manual refresh or move skills/gridpane-tooling/references/
# docs-manifest.json.
#
# Exit status: 0 ran and reported, or nothing to report; 1 scrape, guard or
# delivery failure; 2 usage or configuration error, including an overlapping run;
# 3 changes found but delivery suppressed with --no-email.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SCRAPER="$ROOT/skills/gridpane-tooling/scripts/scrape-docs.sh"
SEED_MANIFEST="$ROOT/skills/gridpane-tooling/references/docs-manifest.json"
CLI="$ROOT/scripts/gridpane-kb-docs.sh"
SKILLS_DIR="$ROOT/skills"
CACHE="$ROOT/out/gridpane-kb-weekly/cache"
STATE="$ROOT/out/gridpane-kb-weekly/state"
EMAIL_SCRIPT="${GRIDPANE_KB_WEEKLY_EMAIL_SCRIPT:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills/send-email/send-email.sh}"
TIMEOUT=1800

DRY_RUN=0
JSON_OUT=0
NO_EMAIL=0

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Report-only weekly check of the GridPane Knowledge Base. Indexes the KB into an
isolated cache, compares it with the baseline the last run acknowledged, and
emails the articles a person should review. Changes nothing in the repository.

Options:
  --dry-run            Print the decision and exit. No network, no lock, no
                       writes, no mail.
  --json               Print one JSON object instead of plain lines.
  --cache DIR          Snapshot cache (default out/gridpane-kb-weekly/cache)
  --state DIR          Baseline, last report and run metadata
                       (default out/gridpane-kb-weekly/state)
  --scraper PATH       Index command to run instead of the bundled scraper. It
                       must write a dated snapshot with manifest.json into --cache
  --seed-manifest FILE Baseline manifest for the first run (default: the
                       committed skills/gridpane-tooling/references/docs-manifest.json)
  --email-script PATH  send-email transport to use (default:
                       ~/.config/opencode/skills/send-email/send-email.sh, or
                       \$GRIDPANE_KB_WEEKLY_EMAIL_SCRIPT)
  --no-email           Build and store the report, deliver nothing; exits 3 when
                       there is something to report
  --timeout SECS       Maximum seconds for the index run (default 1800)
  -h, --help           Show this help and exit

Configuration:
  Mail settings come from the send-email transport (environment first, then its
  config file). This script has no recipient option, by design.

Files written, all under --state unless noted:
  baseline-manifest.json   the manifest the last delivered report acknowledged
  last-report.txt          the report as delivered (or the one held back)
  last-run.json            status, counts, snapshot, baseline, mail result
  run.lock                 held while a run is in progress

Exit status: 0 success, 1 scrape/guard/delivery failure, 2 usage or
configuration error, 3 changes found but not delivered.
EOF
}

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 2; }
have() { command -v "$1" >/dev/null 2>&1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=1; shift ;;
        --json)     JSON_OUT=1; shift ;;
        --no-email) NO_EMAIL=1; shift ;;
        --cache)    CACHE="${2:?--cache needs a value}"; shift 2 ;;
        --cache=*)  CACHE="${1#--cache=}"; shift ;;
        --state)    STATE="${2:?--state needs a value}"; shift 2 ;;
        --state=*)  STATE="${1#--state=}"; shift ;;
        --scraper)  SCRAPER="${2:?--scraper needs a value}"; shift 2 ;;
        --scraper=*) SCRAPER="${1#--scraper=}"; shift ;;
        --seed-manifest) SEED_MANIFEST="${2:?--seed-manifest needs a value}"; shift 2 ;;
        --seed-manifest=*) SEED_MANIFEST="${1#--seed-manifest=}"; shift ;;
        --email-script) EMAIL_SCRIPT="${2:?--email-script needs a value}"; shift 2 ;;
        --email-script=*) EMAIL_SCRIPT="${1#--email-script=}"; shift ;;
        --timeout)  TIMEOUT="${2:?--timeout needs a value}"; shift 2 ;;
        --timeout=*) TIMEOUT="${1#--timeout=}"; shift ;;
        -h|--help)  usage; exit 0 ;;
        -*) log "error: unknown option: $1"; usage >&2; exit 2 ;;
        *)  log "error: unexpected argument: $1 (there is no recipient option)"; exit 2 ;;
    esac
done

have jq || die "jq is required"
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] && [[ "$TIMEOUT" -gt 0 ]] || die "--timeout must be a positive integer"
[[ -x "$SCRAPER" ]] || die "index command not found or not executable: $SCRAPER"
[[ -x "$CLI" ]] || die "not executable: $CLI"

BASELINE="$STATE/baseline-manifest.json"
REPORT="$STATE/last-report.txt"
RUN_LOG="$STATE/last-run.json"
WORK=""

# shellcheck disable=SC2329  # invoked indirectly by the EXIT trap below
cleanup() {
    [[ -n "$WORK" && -d "$WORK" ]] && rm -rf "$WORK"
    return 0
}
trap cleanup EXIT

today() { date -u +%Y-%m-%d; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# --- decisions ---------------------------------------------------------------

# The newest completed snapshot in the cache: the one the diff treats as current.
newest_snapshot() {
    local name="" dir=""
    if [[ -L "$CACHE/latest" ]]; then
        name="$(readlink "$CACHE/latest")"
    elif [[ -f "$CACHE/latest" ]]; then
        name="$(head -1 "$CACHE/latest")"
    fi
    if [[ -n "$name" && -f "$CACHE/$name/manifest.json" ]]; then
        printf '%s' "$name"
        return 0
    fi
    dir="$(find "$CACHE" -maxdepth 1 -type d -name '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]*' \
        2>/dev/null | sort | while IFS= read -r d; do
            [[ -f "$d/manifest.json" ]] && basename "$d"
        done | tail -1)"
    [[ -n "$dir" ]] || return 1
    printf '%s' "$dir"
}

manifest_count() {
    jq -r '.count // 0' "$1" 2>/dev/null || printf '0'
}

# The baseline's own date, used only to describe the comparison in the report.
manifest_date() {
    local fetched
    fetched="$(jq -r '.fetched_at // ""' "$1" 2>/dev/null || true)"
    if [[ -n "$fetched" ]]; then
        printf '%s' "${fetched%%T*}"
    else
        printf 'unknown'
    fi
}

print_decision() {
    local decision="ready" seeded="no"
    [[ -f "$BASELINE" ]] || { decision="first-run"; seeded="yes"; }
    if [[ "$JSON_OUT" -eq 1 ]]; then
        jq -n --arg decision "$decision" --arg baseline "$BASELINE" \
            --arg cache "$CACHE" --arg state "$STATE" --arg scraper "$SCRAPER" \
            --arg seed "$SEED_MANIFEST" --arg email "$EMAIL_SCRIPT" \
            --argjson seeded "$([[ "$seeded" == yes ]] && printf true || printf false)" \
            --argjson email_ready "$([[ -x "$EMAIL_SCRIPT" ]] && printf true || printf false)" \
            '{decision: $decision, dry_run: true, baseline_exists: ($decision == "ready"),
              seed_manifest: $seed, seed_pending: $seeded,
              cache: $cache, state: $state, scraper: $scraper,
              email_script: $email, email_ready: $email_ready}'
    else
        printf 'decision: %s\n' "$decision"
        printf 'baseline: %s (%s)\n' "$BASELINE" \
            "$([[ "$seeded" == yes ]] && printf 'seeded from the committed manifest on this run' || printf 'present')"
        printf 'cache:    %s\n' "$CACHE"
        printf 'state:    %s\n' "$STATE"
        printf 'index:    %s\n' "$SCRAPER"
        printf 'email:    %s (%s)\n' "$EMAIL_SCRIPT" \
            "$([[ -x "$EMAIL_SCRIPT" ]] && printf 'executable' || printf 'not executable: delivery would fail')"
        printf 'dry run:  no network, no lock, no writes, no mail\n'
    fi
}

# --- reporting ---------------------------------------------------------------

# Titles keyed by URL without its trailing slash, which is how the citation rows
# carry them.
title_map() {
    jq -c '[.entries[] | {key: (.url | sub("/$"; "")), value: .title}] | from_entries' "$1"
}

write_report() {
    local snap="$1" manifest="$2" affected="$3" out="$4" date="$5"
    local titles base_date base_count curr_count refs files
    titles="$(title_map "$manifest")"
    base_date="$(manifest_date "$BASELINE")"
    base_count="$(manifest_count "$BASELINE")"
    curr_count="$(manifest_count "$manifest")"
    refs="$(jq -r '.counts.references' "$affected")"
    files="$(jq -r '.counts.files' "$affected")"

    {
        printf 'GridPane KB weekly report — %s\n' "$date"
        printf 'Baseline %s (%s articles) -> snapshot %s (%s articles)\n' \
            "$base_date" "$base_count" "$snap" "$curr_count"
        printf 'Changes: %s\n\n' "$(status_summary "$affected")"
        printf 'Review candidates — cited by a skill: %s references in %s files\n' \
            "$refs" "$files"
        if [[ "$refs" -eq 0 ]]; then
            printf '  (none)\n'
        fi
        jq -r --argjson titles "$titles" '
            [.rows[] | select(.file != null)]
            | sort_by(.file, .line) | .[0:60]
            | .[] | "  \(.file):\(.line)\n    \(.status)  \($titles[.url] // "(title unavailable)")\n    \(.url)"' \
            "$affected"
        jq -r '[.rows[] | select(.file != null)] | length' "$affected" \
            | awk -v n=60 '$1 > n { printf "  (+%d more references)\n", $1 - n }'
        printf '\nNot cited by any skill\n'
        jq -r --argjson titles "$titles" '
            [.rows[] | select(.file == null)] | sort_by(.status, .url)
            | if length == 0 then "  (none)"
              else (.[0:40] | .[] | "  \(.status)  \($titles[.url] // "(title unavailable)")\n    \(.url)") end' \
            "$affected"
        jq -r '[.rows[] | select(.file == null)] | length' "$affected" \
            | awk -v n=40 '$1 > n { printf "  (+%d more articles)\n", $1 - n }'
        printf '\nNotes\n'
        printf '  "changed" means the rendered body hash differs; the wording may be\n'
        printf '  identical. Read the article before editing a citation.\n'
        printf '  Act with the gridpane-kb-refresh skill: scripts/gridpane-kb-docs.sh\n'
        printf '  refresh, then affected. This report changed nothing on its own.\n'
        printf '  An uncited article may deserve a citation, or may be irrelevant.\n'
    } > "$out"
}

# Distinct articles per status, for the header line.
status_summary() {
    jq -r '
        [.rows[]] | group_by(.url) | map(.[0].status)
        | group_by(.) | map({key: .[0], value: length}) | from_entries
        | "\(.added // 0) added, \(.removed // 0) removed, \(.changed // 0) changed, \(.title // 0) title-only"' \
        "$1"
}

changed_articles() {
    jq -r '[.rows[].url] | unique | length' "$1"
}

subject_for() {
    local count="$1" date="$2"
    printf 'GridPane KB weekly: %s article(s) need review (%s)' "$count" "$date"
}

# --- delivery ----------------------------------------------------------------

send_mail() {
    local subject="$1" body="$2"
    if [[ ! -x "$EMAIL_SCRIPT" ]]; then
        log "error: mail transport not executable: $EMAIL_SCRIPT"
        return 1
    fi
    if timeout 180 "$EMAIL_SCRIPT" "$subject" < "$body"; then
        return 0
    fi
    log "error: mail transport failed for: $subject"
    return 1
}

record_run() {
    local status="$1" email="$2" snap="$3" affected="$4" date="$5"
    local counts="{}"
    if [[ -n "$affected" && -f "$affected" ]]; then
        counts="$(jq -c '.counts' "$affected")"
    fi
    jq -n --arg status "$status" --arg at "$(now)" --arg date "$date" \
        --arg snapshot "$snap" --arg baseline "$BASELINE" \
        --arg report "$REPORT" --argjson counts "$counts" --arg email "$email" \
        '{status: $status, at: $at, date: $date, snapshot: $snapshot,
          baseline: $baseline, counts: $counts, email: $email, report: $report}' \
        > "$RUN_LOG"
}

advance_baseline() {
    local manifest="$1" tmp
    tmp="$(mktemp "$STATE/.baseline.XXXXXX")"
    cp "$manifest" "$tmp"
    mv "$tmp" "$BASELINE"
}

fail_run() {
    local reason="$1" detail="$2" snap="${3:-unknown}" affected="${4:-}"
    local date body
    date="$(today)"
    body="$(mktemp)"
    {
        printf 'GridPane KB weekly run failed — %s\n\n' "$date"
        printf '%s\n\n' "$reason"
        if [[ -n "$detail" ]]; then
            printf 'Details\n%s\n\n' "$detail"
        fi
        printf 'The baseline was not advanced, so the next run recomputes these changes.\n'
        printf 'Baseline: %s\nState:    %s\n' "$BASELINE" "$STATE"
    } > "$body"
    cp "$body" "$REPORT"
    log "error: $reason"
    mail_result="not-sent"
    if [[ "$NO_EMAIL" -eq 0 ]]; then
        if send_mail "GridPane KB weekly: FAILED ($date)" "$body"; then
            mail_result="ok"
        else
            mail_result="failed"
            log "error: the failure notification could not be sent either"
        fi
    fi
    record_run "failed" "$mail_result" "$snap" "$affected" "$date"
    rm -f "$body"
    exit 1
}

# --- run ---------------------------------------------------------------------

if [[ "$DRY_RUN" -eq 1 ]]; then
    print_decision
    exit 0
fi

mkdir -p "$STATE"
exec 9>"$STATE/run.lock"
if ! flock -n 9; then
    die "already running: another $SCRIPT_NAME holds $STATE/run.lock"
fi

mkdir -p "$CACHE"

if [[ ! -f "$BASELINE" ]]; then
    [[ -f "$SEED_MANIFEST" ]] \
        || fail_run "first run has no seed manifest" "missing: $SEED_MANIFEST"
    cp "$SEED_MANIFEST" "$BASELINE"
    log "first run: seeded the baseline from $SEED_MANIFEST"
fi

date_today="$(today)"
WORK="$(mktemp -d)"
scrape_log="$WORK/index.log"

if ! timeout "$TIMEOUT" "$SCRAPER" --cache "$CACHE" >"$scrape_log" 2>&1; then
    fail_run "the index run failed" "$(tail -12 "$scrape_log")"
fi

snap="$(newest_snapshot)" \
    || fail_run "the index run produced no completed snapshot" "$(tail -5 "$scrape_log")"
manifest="$CACHE/$snap/manifest.json"
affected="$WORK/affected.json"

if ! "$CLI" affected --prev-manifest "$BASELINE" --all --json \
        --cache "$CACHE" --skills "$SKILLS_DIR" >"$affected" 2>"$WORK/affected.err"; then
    fail_run "the comparison against the baseline failed" \
        "$(tail -5 "$WORK/affected.err")" "$snap"
fi
jq -e '.rows | type == "array"' "$affected" >/dev/null 2>&1 \
    || fail_run "the comparison produced no usable JSON" "$(head -3 "$affected")" "$snap"

changed="$(changed_articles "$affected")"
refs="$(jq -r '.counts.references' "$affected")"

if [[ "$changed" -eq 0 ]]; then
    advance_baseline "$manifest"
    record_run "no-change" "not-sent" "$snap" "$affected" "$date_today"
    log "no article changes since the baseline; nothing to send"
    if [[ "$JSON_OUT" -eq 1 ]]; then
        jq -n --arg snapshot "$snap" --arg date "$date_today" \
            '{result: "no-change", changed: 0, snapshot: $snapshot, date: $date}'
    else
        printf 'result: no-change (0 articles)\nsnapshot: %s\n' "$snap"
    fi
    exit 0
fi

tmp_report="$STATE/.report.XXXXXX"
tmp_report="$(mktemp "$tmp_report")"
write_report "$snap" "$manifest" "$affected" "$tmp_report" "$date_today"
mv "$tmp_report" "$REPORT"

subject="$(subject_for "$changed" "$date_today")"

if [[ "$NO_EMAIL" -eq 1 ]]; then
    record_run "held" "suppressed" "$snap" "$affected" "$date_today"
    log "$changed article(s) changed; report held at $REPORT (--no-email)"
    if [[ "$JSON_OUT" -eq 1 ]]; then
        jq -n --arg snapshot "$snap" --arg report "$REPORT" --argjson changed "$changed" \
            '{result: "held", changed: $changed, snapshot: $snapshot, report: $report}'
    else
        printf 'result: held (%s articles, not sent)\nreport: %s\n' "$changed" "$REPORT"
    fi
    exit 3
fi

if send_mail "$subject" "$REPORT"; then
    advance_baseline "$manifest"
    record_run "sent" "ok" "$snap" "$affected" "$date_today"
    log "sent: $subject ($refs references)"
    if [[ "$JSON_OUT" -eq 1 ]]; then
        jq -n --arg snapshot "$snap" --arg report "$REPORT" --argjson changed "$changed" \
            --argjson refs "$refs" --arg subject "$subject" \
            '{result: "sent", changed: $changed, references: $refs,
              snapshot: $snapshot, report: $report, subject: $subject}'
    else
        printf 'result: sent (%s articles, %s references)\nsnapshot: %s\n' \
            "$changed" "$refs" "$snap"
    fi
    exit 0
fi

record_run "delivery-failed" "failed" "$snap" "$affected" "$date_today"
log "error: the report was built but not delivered; it stays at $REPORT"
log "error: the baseline was not advanced, so the next run retries these changes"
exit 1
