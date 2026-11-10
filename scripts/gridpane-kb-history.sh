#!/usr/bin/env bash
#
# gridpane-kb-history.sh - render the weekly KB report ledger as Markdown history.
#
# The weekly runner (gridpane-kb-weekly.sh) records one JSON object per completed
# comparison under its gitignored state directory. This script turns that ledger
# into KB-CHANGES.md: every monitored change to the GridPane Knowledge Base,
# newest first, grouped by year and month, with the articles and the skill
# locations that cite them.
#
# It is read-only towards the repository: the only file it writes is --out.
# Nothing here makes a network request, and the weekly run never writes a tracked
# file, so history reaches git only when a person renders and commits it.
#
# Backfill (--backfill) reads the completed snapshots already under the caches,
# diffs consecutive dates by sha256, and appends one record per interval to the
# ledger. Run it once after upgrading, or whenever snapshots exist without a
# ledger record.
#
# Exit status: 0 rendered or --check found the file current; 1 missing ledger,
# unreadable snapshot or write failure; 2 usage error; 3 --check found the file
# stale (nothing is written).

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LEDGER="$ROOT/out/gridpane-kb-weekly/state/history.jsonl"
OUT_FILE="$ROOT/KB-CHANGES.md"
CACHES=()
BACKFILL=0
CHECK=0
TO_STDOUT=0
JSON_OUT=0

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Render the weekly KB report ledger as a human-readable history, grouped by year
and month. Read-only apart from --out; no network.

Options:
  --ledger FILE   Run history written by the weekly job
                  (default out/gridpane-kb-weekly/state/history.jsonl)
  --cache DIR     Snapshot cache to backfill from; repeatable
                  (default: out/gridpane-docs-cache and
                  out/gridpane-kb-weekly/cache)
  --out FILE      Markdown file to write (default KB-CHANGES.md)
  --stdout        Print the Markdown instead of writing a file
  --backfill      Append a record per snapshot interval the ledger lacks, then
                  render
  --check         Compare the rendered history with --out and write nothing;
                  exit 3 when it differs
  --json          Print the month aggregate as JSON instead of Markdown
  -h, --help      Show this help and exit

Files written, only when rendering:
  --out           the Markdown history (a temporary file is renamed into place)
  --ledger        one line per backfilled interval, with --backfill

Records are deduplicated by baseline: a held or failed delivery leaves the
baseline in place, so the run that finally reports that interval replaces the
earlier attempt. A delivered record outranks a held, failed or backfilled one.

Exit status: 0 success, 1 missing input or write failure, 2 usage error,
3 --check found the file stale.
EOF
}

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit "${2:-1}"; }
have() { command -v "$1" >/dev/null 2>&1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ledger)   LEDGER="${2:?--ledger needs a value}"; shift 2 ;;
        --ledger=*) LEDGER="${1#--ledger=}"; shift ;;
        --cache)    CACHES+=("${2:?--cache needs a value}"); shift 2 ;;
        --cache=*)  CACHES+=("${1#--cache=}"); shift ;;
        --out)      OUT_FILE="${2:?--out needs a value}"; shift 2 ;;
        --out=*)    OUT_FILE="${1#--out=}"; shift ;;
        --stdout)   TO_STDOUT=1; shift ;;
        --backfill) BACKFILL=1; shift ;;
        --check)    CHECK=1; shift ;;
        --json)     JSON_OUT=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        -*) log "error: unknown option: $1"; usage >&2; exit 2 ;;
        *)  log "error: unexpected argument: $1"; usage >&2; exit 2 ;;
    esac
done

have jq || die "jq is required"
[[ $BACKFILL -eq 1 && $CHECK -eq 1 ]] \
    && die "--backfill writes the ledger, so it cannot be combined with --check" 2

if [[ ${#CACHES[@]} -eq 0 ]]; then
    CACHES=("$ROOT/out/gridpane-docs-cache" "$ROOT/out/gridpane-kb-weekly/cache")
fi
[[ "$LEDGER" = /* ]] || LEDGER="$ROOT/$LEDGER"
[[ "$OUT_FILE" = /* ]] || OUT_FILE="$ROOT/$OUT_FILE"

WORK=""
cleanup() {
    if [[ -n "$WORK" ]]; then rm -rf "$WORK"; fi
    return 0
}
trap cleanup EXIT
WORK="$(mktemp -d)"

month_label() {
    date -u -d "$1-01" '+%B %Y' 2>/dev/null || printf '%s' "$1"
}

# --- backfill ----------------------------------------------------------------

# Completed snapshots as "<fetched_at>\t<date>\t<dir>", one per date (the last
# fetch wins, so a day with several runs contributes one interval, not many).
snapshot_rows() {
    local cache dir base date iso
    for cache in "${CACHES[@]}"; do
        [[ -d "$cache" ]] || continue
        for dir in "$cache"/*; do
            [[ -d "$dir" ]] || continue
            [[ -f "$dir/manifest.json" ]] || continue
            base="$(basename "$dir")"
            [[ "$base" == "latest" ]] && continue
            date="$base"
            if [[ "$base" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})-[0-9]+$ ]]; then
                date="${BASH_REMATCH[1]}"
            fi
            iso="$(jq -r '.fetched_at // ""' "$dir/manifest.json" 2>/dev/null || true)"
            [[ -n "$iso" ]] || continue
            printf '%s\t%s\t%s\n' "$iso" "$date" "$dir"
        done
    done | LC_ALL=C sort | awk -F'\t' '{ last[$2] = $0 } END { for (d in last) print last[d] }' \
        | LC_ALL=C sort
}

# One interval as a ledger record: added, removed, body-changed and title-only
# articles, with titles resolved from either manifest and no citations (the
# ledger records what the run saw, and a backfill cannot know what was cited
# then).
backfill_record() {
    local prev_dir="$1" curr_dir="$2" prev_date="$3" date="$4" snap="$5"
    jq -n -c --slurpfile a "$prev_dir/manifest.json" --slurpfile b "$curr_dir/manifest.json" \
        --arg date "$date" --arg snap "$snap" --arg baseline "$prev_date" '
        ($a[0].entries | map({key: .url, value: .}) | from_entries) as $am
        | ($b[0].entries | map({key: .url, value: .}) | from_entries) as $bm
        | ( [ $bm | keys[] | select($am[.] == null)
              | {status: "added", url: ., title: ($bm[.].title // "")} ]
          + [ $bm | keys[] | select($am[.] != null and $am[.].sha256 != $bm[.].sha256)
              | {status: "changed", url: ., title: ($bm[.].title // "")} ]
          + [ $am | keys[] | select($bm[.] == null)
              | {status: "removed", url: ., title: ($am[.].title // "")} ]
          + [ $bm | keys[] | select($am[.] != null and $am[.].sha256 == $bm[.].sha256
              and $am[.].title != $bm[.].title)
              | {status: "title", url: ., title: ($bm[.].title // "")} ] ) as $rows
        | ($rows | map(.url |= sub("/$"; ""))) as $articles
        | {schema: 1, date: $date, snapshot: $snap, baseline: $baseline,
           result: "backfilled",
           counts: {
               added: ([$articles[] | select(.status == "added")] | length),
               removed: ([$articles[] | select(.status == "removed")] | length),
               changed: ([$articles[] | select(.status == "changed")] | length),
               title_only: ([$articles[] | select(.status == "title")] | length),
               references: 0, files: 0},
           articles: ($articles | map(. + {citations: []}))}'
}

ledger_has_interval() {
    local baseline="$1" snap="$2"
    [[ -f "$LEDGER" ]] || return 1
    jq -s -e --arg b "$baseline" --arg s "$snap" '
        [ .[] | select(type == "object" and .result == "backfilled"
                       and .baseline == $b and .snapshot == $s) ] | length > 0' \
        "$LEDGER" >/dev/null 2>&1
}

backfill_ledger() {
    local rows record added=0 i
    local -a isos=() dates=() dirs=()
    rows="$(snapshot_rows)"
    if [[ -z "$rows" ]]; then
        log "backfill: no completed snapshot in ${CACHES[*]}"
        return 0
    fi
    while IFS=$'\t' read -r iso date dir; do
        [[ -n "$iso" ]] || continue
        isos+=("$iso"); dates+=("$date"); dirs+=("$dir")
    done <<<"$rows"
    if [[ ${#isos[@]} -lt 2 ]]; then
        log "backfill: one snapshot only; nothing to compare"
        return 0
    fi
    mkdir -p "$(dirname "$LEDGER")"
    for ((i = 1; i < ${#isos[@]}; i++)); do
        if ! record="$(backfill_record "${dirs[$((i - 1))]}" "${dirs[$i]}" \
                "${dates[$((i - 1))]}" "${dates[$i]}" "$(basename "${dirs[$i]}")")"; then
            log "backfill: could not read ${dirs[$i]#"$ROOT"/}/manifest.json"
            return 1
        fi
        if ledger_has_interval "${dates[$((i - 1))]}" "$(basename "${dirs[$i]}")"; then
            continue
        fi
        printf '%s\n' "$record" >> "$LEDGER"
        added=$((added + 1))
    done
    log "backfill: $added interval(s) added to ${LEDGER#"$ROOT"/}"
}

# --- render ------------------------------------------------------------------

# Records deduplicated by baseline: the interval the run finally reported wins
# over an earlier held, failed or backfilled attempt.
records_json() {
    jq -s '
        def rank:
            if .result == "sent" then 4
            elif .result == "no-change" then 3
            elif .result == "held" then 2
            elif .result == "delivery-failed" then 1
            else 0 end;
        [ .[] | select(type == "object" and (.schema // 0) == 1
                       and (.baseline // "") != "" and (.date // "") != "") ]
        | to_entries
        | map(.value + {__i: .key})
        | sort_by(.baseline, rank, .__i)
        | group_by(.baseline)
        | map(last | del(.__i))
        | sort_by(.date, .snapshot)
        | reverse' "$LEDGER"
}

# "2026-11" -> "November 2026", passed to jq as a label map.
month_labels() {
    local records="$1" labels='{}' month
    while IFS= read -r month; do
        [[ -n "$month" ]] || continue
        labels="$(jq -c --arg k "$month" --arg v "$(month_label "$month")" \
            '. + {($k): $v}' <<<"$labels")"
    done < <(printf '%s' "$records" | jq -r '[.[].date[0:7]] | unique | .[]')
    printf '%s' "$labels"
}

render_markdown() {
    local dest="$1" records labels
    records="$(records_json)"
    if [[ "$(printf '%s' "$records" | jq 'length')" -eq 0 ]]; then
        {
            printf '# GridPane KB change history\n\n'
            printf 'No changes have been recorded yet. Generate the first entry by\n'
            printf 'running scripts/gridpane-kb-history.sh --backfill.\n'
        } >"$dest"
        return 0
    fi
    labels="$(month_labels "$records")"
    printf '%s' "$records" | jq -r --argjson labels "$labels" '
        def status_label: if . == "title" then "title-only" else . end;
        def status_rank: {"added": 0, "removed": 1, "changed": 2, "title": 3}[.] // 9;
        def bullet($backfilled):
            "- \(.status | status_label) — [\(if .title == "" then .url else .title end)](\(.url))"
            + (if $backfilled then ""
               elif (.citations | length) > 0 then
                   " — cited by " + ([.citations[] | "`\(.)`"] | join(", "))
               else " — uncited" end);
        def block:
            (.result == "backfilled") as $backfilled
            | "**\(.date)** · snapshot `\(.snapshot)` · baseline `\(.baseline)` · \(.result)\n"
            + "\(.counts.added // 0) added · \(.counts.removed // 0) removed"
            + " · \(.counts.changed // 0) changed · \(.counts.title_only // 0) title-only\n"
            + (if $backfilled then
                   "Backfilled from the snapshot manifests; citations were not recorded.\n"
               else "" end)
            + (if (.articles | length) == 0 then "- no article changes"
               else ([.articles[]] | sort_by((.status | status_rank), .title)
                     | map(bullet($backfilled)) | join("\n")) end);
        . as $all
        | ([$all[].date[0:7]] | unique | sort | reverse) as $months
        | ([$all[].date[0:4]] | unique | sort | reverse) as $years
        | ( "# GridPane KB change history\n\n"
          + "Every monitored change to the GridPane Knowledge Base, newest first,\n"
          + "grouped by year and month. One entry per reporting interval; a body\n"
          + "\"change\" means the rendered article hash moved, which can be markup\n"
          + "only — read the article before editing a citation.\n\n"
          + "Generated by `scripts/gridpane-kb-history.sh` from the weekly report\n"
          + "ledger; edit the ledger or the script, never this file by hand.\n\n"
          + "- Ledger: `out/gridpane-kb-weekly/state/history.jsonl` (local, gitignored)\n"
          + "- Regenerate: `scripts/gridpane-kb-history.sh --backfill`\n"
          + "- Check: `scripts/gridpane-kb-history.sh --check`\n"
          + "- History begins at the earliest retained snapshot in the local cache.\n\n"
          + "## At a glance\n\n"
          + "| Month | Reports | Added | Removed | Changed | Title-only |\n"
          + "|---|---:|---:|---:|---:|---:|\n"
          + ([ $months[] | . as $m
               | ($all | map(select(.date[0:7] == $m))) as $g
               | "| \($labels[$m]) | \($g | length) | "
                 + "\([$g[].counts.added // 0] | add) | \([$g[].counts.removed // 0] | add) | "
                 + "\([$g[].counts.changed // 0] | add) | \([$g[].counts.title_only // 0] | add) |"
             ] | join("\n"))
          + "\n"
          + ([ $years[] | . as $y
               | "\n## \($y)\n"
                 + ([ $months[] | select(startswith($y + "-")) | . as $m
                      | "\n### \($labels[$m])\n\n"
                        + ([ $all[] | select(.date[0:7] == $m) | block ] | join("\n\n"))
                    ] | join("\n"))
             ] | join("\n"))
          )
    ' >"$dest"
}

# --- run ---------------------------------------------------------------------

if [[ $BACKFILL -eq 1 ]]; then
    backfill_ledger
fi

[[ -f "$LEDGER" ]] || die "ledger not found: ${LEDGER#"$ROOT"/} (run the weekly report, or --backfill)"

TMP_MD="$WORK/history.md"
render_markdown "$TMP_MD"

if [[ $JSON_OUT -eq 1 ]]; then
    records_json >"$WORK/records.json"
    labels="$(month_labels "$(cat "$WORK/records.json")")"
    jq --arg ledger "${LEDGER#"$ROOT"/}" --argjson labels "$labels" '
        {ledger: $ledger,
         records: length,
         months: (group_by(.date[0:7])
            | map({month: (.[0].date[0:7]),
                   label: $labels[(.[0].date[0:7])],
                   reports: length,
                   added: (map(.counts.added // 0) | add),
                   removed: (map(.counts.removed // 0) | add),
                   changed: (map(.counts.changed // 0) | add),
                   title_only: (map(.counts.title_only // 0) | add)})
            | sort_by(.month) | reverse)}' "$WORK/records.json"
    exit 0
fi

if [[ $CHECK -eq 1 ]]; then
    if [[ ! -f "$OUT_FILE" ]]; then
        log "stale: ${OUT_FILE#"$ROOT"/} does not exist; run ${SCRIPT_NAME} --backfill"
        exit 3
    fi
    if cmp -s "$TMP_MD" "$OUT_FILE"; then
        log "current: ${OUT_FILE#"$ROOT"/} matches the ledger"
        exit 0
    fi
    log "stale: ${OUT_FILE#"$ROOT"/} differs from the ledger; run ${SCRIPT_NAME} --backfill"
    exit 3
fi

if [[ $TO_STDOUT -eq 1 ]]; then
    cat "$TMP_MD"
    exit 0
fi

mkdir -p "$(dirname "$OUT_FILE")"
mv "$TMP_MD" "$OUT_FILE"
log "wrote ${OUT_FILE#"$ROOT"/}"
