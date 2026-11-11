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
EMIT_DIFFS=0
BASE_LABEL=""
AFFECTED=""
DATE=""
SNAP_DIR=""
BASE_SNAP=""
BASE_MANIFEST=""
STATE="$ROOT/out/gridpane-kb-weekly/state"
SCRAPER="$ROOT/skills/gridpane-tooling/scripts/scrape-docs.sh"
CHANGES_DIR="$ROOT/kb-changes"

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
  --changes-dir DIR
                  Diff tree to write beside it (default kb-changes)
  --stdout        Print the Markdown instead of writing a file (the diff tree
                  is not printed)
  --backfill      Append a record per snapshot interval the ledger lacks, then
                  render
  --check         Compare the rendered history with --out and write nothing;
                  exit 3 when it differs
  --json          Print the month aggregate as JSON instead of Markdown
  --emit-diffs    Write one changed-hunk diff per article under
                  --state/diffs/<date>/ and print the list instead of rendering
  --affected FILE The affected JSON --emit-diffs reads (required with it)
  --date DATE     The interval date for --emit-diffs (required with it)
  --snapshot DIR  The snapshot --emit-diffs compares against (required with it)
  --baseline-manifest FILE
                  The baseline manifest --emit-diffs resolves to a snapshot by
                  content across --cache directories
  --baseline-snapshot DIR
                  The baseline snapshot directory, instead of resolving one
  --state DIR     Where --emit-diffs writes (default
                  out/gridpane-kb-weekly/state)
  --scraper PATH  Extraction engine for --emit-diffs (default
                  skills/gridpane-tooling/scripts/scrape-docs.sh)
  -h, --help      Show this help and exit

Files written, only when rendering:
  --out           the Markdown history (a temporary file is renamed into place)
  --changes-dir   one diff file per article per interval, plus its README; only
                  files named <YYYY>/<MM>/<date>-<slug>.md are ever removed, and
                  only when the ledger no longer produces them
  --ledger        one line per backfilled interval, with --backfill

--emit-diffs writes one file per article the affected JSON reports, at
<state>/diffs/<date>/<date>-<slug>.md, and never a whole article body: a new
article is a stub, a removed one is a note, and a title-only change records the
two titles. It prints "slug<TAB>kind<TAB>file" per article, or one JSON object
with --json.

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
        --changes-dir)   CHANGES_DIR="${2:?--changes-dir needs a value}"; shift 2 ;;
        --changes-dir=*) CHANGES_DIR="${1#--changes-dir=}"; shift ;;
        --stdout)   TO_STDOUT=1; shift ;;
        --backfill) BACKFILL=1; shift ;;
        --check)    CHECK=1; shift ;;
        --json)     JSON_OUT=1; shift ;;
        --emit-diffs)       EMIT_DIFFS=1; shift ;;
        --affected)         AFFECTED="${2:?--affected needs a value}"; shift 2 ;;
        --affected=*)       AFFECTED="${1#--affected=}"; shift ;;
        --date)             DATE="${2:?--date needs a value}"; shift 2 ;;
        --date=*)           DATE="${1#--date=}"; shift ;;
        --snapshot)         SNAP_DIR="${2:?--snapshot needs a value}"; shift 2 ;;
        --snapshot=*)       SNAP_DIR="${1#--snapshot=}"; shift ;;
        --baseline-manifest)   BASE_MANIFEST="${2:?--baseline-manifest needs a value}"; shift 2 ;;
        --baseline-manifest=*) BASE_MANIFEST="${1#--baseline-manifest=}"; shift ;;
        --baseline-snapshot)   BASE_SNAP="${2:?--baseline-snapshot needs a value}"; shift 2 ;;
        --baseline-snapshot=*) BASE_SNAP="${1#--baseline-snapshot=}"; shift ;;
        --state)            STATE="${2:?--state needs a value}"; shift 2 ;;
        --state=*)          STATE="${1#--state=}"; shift ;;
        --scraper)          SCRAPER="${2:?--scraper needs a value}"; shift 2 ;;
        --scraper=*)        SCRAPER="${1#--scraper=}"; shift ;;
        -h|--help)  usage; exit 0 ;;
        -*) log "error: unknown option: $1"; usage >&2; exit 2 ;;
        *)  log "error: unexpected argument: $1"; usage >&2; exit 2 ;;
    esac
done

have jq || die "jq is required"
[[ $BACKFILL -eq 1 && $CHECK -eq 1 ]] \
    && die "--backfill writes the ledger, so it cannot be combined with --check" 2
if [[ $EMIT_DIFFS -eq 1 ]]; then
    [[ $BACKFILL -eq 0 && $CHECK -eq 0 ]] \
        || die "--emit-diffs is its own mode; drop --backfill and --check" 2
    [[ -n "$AFFECTED" ]] || die "--emit-diffs needs --affected FILE" 2
    [[ -n "$DATE" ]] || die "--emit-diffs needs --date YYYY-MM-DD" 2
    [[ -n "$SNAP_DIR" ]] || die "--emit-diffs needs --snapshot DIR" 2
    [[ -n "$BASE_SNAP" || -n "$BASE_MANIFEST" ]] \
        || die "--emit-diffs needs --baseline-manifest FILE or --baseline-snapshot DIR" 2
fi

if [[ ${#CACHES[@]} -eq 0 ]]; then
    CACHES=("$ROOT/out/gridpane-docs-cache" "$ROOT/out/gridpane-kb-weekly/cache")
fi
[[ "$LEDGER" = /* ]] || LEDGER="$ROOT/$LEDGER"
[[ "$OUT_FILE" = /* ]] || OUT_FILE="$ROOT/$OUT_FILE"
[[ "$STATE" = /* ]] || STATE="$ROOT/$STATE"
[[ "$CHANGES_DIR" = /* ]] || CHANGES_DIR="$ROOT/$CHANGES_DIR"
[[ "$AFFECTED" = /* || -z "$AFFECTED" ]] || AFFECTED="$ROOT/$AFFECTED"
[[ "$BASE_MANIFEST" = /* || -z "$BASE_MANIFEST" ]] || BASE_MANIFEST="$ROOT/$BASE_MANIFEST"

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

# --- diffs -------------------------------------------------------------------

# A committed diff file stops growing here, at a hunk boundary or, when a single
# hunk is larger than the budget, at a line boundary. A pathological rewrite
# would otherwise put hundreds of kilobytes of article text in one file; the
# article link in the header is the escape hatch.
DIFF_CAP=65536

# "https://gridpane.com/kb/migrately" -> "migrately"
slug_of_url() {
    local url="${1%/}"
    printf '%s' "${url##*/}"
}

# The interval a snapshot directory stands for, as YYYY-MM-DD: the manifest's
# fetch date when it has one, else the directory name with any -N suffix
# dropped.
snapshot_day() {
    local dir="$1" day=""
    if [[ -f "$dir/manifest.json" ]]; then
        day="$(jq -r '.fetched_at // ""' "$dir/manifest.json" 2>/dev/null || true)"
    fi
    [[ -n "$day" ]] || day="$(basename "$dir")"
    if [[ "$day" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
        day="${BASH_REMATCH[1]}"
    fi
    printf '%s' "$day"
}

# An article's title from a snapshot manifest; empty when it is not there.
snapshot_title() {
    local dir="$1" url="${2%/}"
    [[ -f "$dir/manifest.json" ]] || { printf ''; return 0; }
    jq -r --arg u "$url" '
        [.entries[] | select((.url | sub("/$"; "")) == $u)][0].title // ""' \
        "$dir/manifest.json" 2>/dev/null || true
}

# The baseline manifest is a byte copy of the snapshot manifest it came from,
# so identity is an exact test rather than a date guess.
resolve_baseline_snapshot() {
    local want="$1" cache dir
    for cache in "${CACHES[@]}"; do
        [[ -d "$cache" ]] || continue
        for dir in "$cache"/*/; do
            [[ -f "$dir/manifest.json" ]] || continue
            if cmp -s "$want" "$dir/manifest.json"; then
                printf '%s' "${dir%/}"
                return 0
            fi
        done
    done
    return 1
}

# One article's extracted text, through the scraper so the converter is never
# duplicated. The scraper writes <snapshot>/<slug>.md into the gitignored cache,
# which is its documented extract behaviour; the copy keeps the snapshot clean
# enough for the next run to overwrite without reading its own output.
extract_body() {
    local dir="$1" slug="$2" dest="$3" abs
    [[ -d "$dir" ]] || return 1
    abs="$(cd "$dir" && pwd)"
    rm -f "$abs/$slug.md"
    if ! "$SCRAPER" --cache "$(dirname "$abs")" --snapshot "$abs" \
            --slug "$slug" --format markdown --no-pandoc \
            >/dev/null 2>>"$WORK/extract.log"; then
        return 1
    fi
    [[ -s "$abs/$slug.md" ]] || return 1
    cp "$abs/$slug.md" "$dest"
}

# Header every diff file carries: what moved, where to read it, and who cites it.
diff_header() {
    local title="$1" status="$2" base_day="$3" day="$4" url="$5" cites="$6"
    printf '# %s\n\n' "${title:-$url}"
    printf -- '- Status: %s\n' "$status"
    printf -- '- Interval: %s → %s\n' "$base_day" "$day"
    printf -- '- Article: %s\n' "$url"
    if [[ -n "$cites" ]]; then
        printf -- '- Cited by: %s\n' "$cites"
    else
        # shellcheck disable=SC2016  # literal Markdown backticks, not a command
        printf -- '- Cited by: nothing in `skills/`\n'
    fi
    printf -- '- Extracted text, not the published HTML: code blocks and tables may reflow.\n\n'
}

# Truncate a unified diff at DIFF_CAP bytes, at a hunk boundary when one fits and
# at a line boundary otherwise, and say so. LC_ALL=C keeps length() in bytes.
cap_diff() {
    local raw="$1" out="$2"
    LC_ALL=C awk -v cap="$DIFF_CAP" '
        BEGIN { total = 0; hunk = ""; stopped = 0 }
        /^@@/ {
            if (hunk != "") {
                if (stopped || total + length(hunk) > cap) {
                    stopped = 1
                } else {
                    printf "%s", hunk
                    total += length(hunk)
                }
                hunk = ""
            }
            if (!stopped) { hunk = $0 "\n" }
            next
        }
        {
            if (hunk == "") {
                if (!stopped) { print; total += length($0) + 1 }
                next
            }
            if (stopped) next
            hunk = hunk $0 "\n"
        }
        END {
            if (stopped) {
                printf "\n… Diff truncated at %d KB; open the article for the rest.\n", cap / 1024
                exit
            }
            if (total + length(hunk) <= cap) { printf "%s", hunk; exit }
            n = split(hunk, lines, "\n")
            room = cap - total
            for (i = 1; i <= n; i++) {
                if (length(lines[i]) + 1 > room) break
                print lines[i]
                room -= length(lines[i]) + 1
            }
            printf "\n… Diff truncated at %d KB; open the article for the rest.\n", cap / 1024
        }' "$raw" >"$out"
}

# Write one article's file. Returns the diff kind through DIFF_KIND and the
# file name through DIFF_FILE (empty when no file is worth writing).
write_article_diff() {
    local status="$1" url="$2" cites="$3" base_dir="$4" snap_dir="$5"
    local base_day="$6" day="$7" out_dir="$8"
    local slug title new_title old_title kind="" file="" size=0
    slug="$(slug_of_url "$url")"
    # affected reports file:line against the tree it scanned, which is absolute
    # when --skills is; a committed file must not carry a workstation path, so
    # every citation is rewritten to its repository-relative form.
    cites="$(printf '%s' "$cites" | sed -E 's#[^ `]+/skills/#skills/#g')"
    title="$(snapshot_title "$snap_dir" "$url")"
    [[ -n "$title" ]] || title="$(snapshot_title "$base_dir" "$url")"
    file="$day-$slug.md"

    case "$status" in
        added)
            kind="added"
            if extract_body "$snap_dir" "$slug" "$WORK/new.md"; then
                size="$(wc -c <"$WORK/new.md" | tr -d ' ')"
            fi
            {
                diff_header "$title" "added" "$base_day" "$day" "$url" "$cites"
                printf '## New article\n\n'
                printf 'Added to the KB in this interval, so there is no earlier version to diff. '
                if [[ "$size" -gt 0 ]]; then
                    printf 'The extracted text is %s bytes; read it at %s.\n' "$size" "$url"
                else
                    printf 'Read it at %s.\n' "$url"
                fi
            } >"$out_dir/$file"
            ;;
        removed)
            kind="removed"
            {
                diff_header "$title" "removed" "$base_day" "$day" "$url" "$cites"
                printf '## Removed article\n\n'
                printf 'The URL no longer appears in the KB index. The last recorded title is "%s".\n' \
                    "$title"
            } >"$out_dir/$file"
            ;;
        title)
            kind="title"
            new_title="$(snapshot_title "$snap_dir" "$url")"
            old_title="$(snapshot_title "$base_dir" "$url")"
            {
                diff_header "$new_title" "title-only" "$base_day" "$day" "$url" "$cites"
                printf '## Title change\n\n'
                printf -- '- Before: %s\n' "${old_title:-unknown}"
                printf -- '- After: %s\n\n' "${new_title:-unknown}"
                printf 'The body text is unchanged.\n'
            } >"$out_dir/$file"
            ;;
        changed)
            if ! extract_body "$base_dir" "$slug" "$WORK/old.md" \
                    || ! extract_body "$snap_dir" "$slug" "$WORK/new.md"; then
                kind="unavailable"
                file=""
            elif cmp -s "$WORK/old.md" "$WORK/new.md"; then
                kind="markup-only"
                {
                    diff_header "$title" "changed" "$base_day" "$day" "$url" "$cites"
                    printf '## No text change\n\n'
                    printf 'The extracted text is identical in both snapshots; the rendered-HTML\n'
                    printf 'hash changed (markup only). Nothing here needs a citation edit.\n'
                } >"$out_dir/$file"
            else
                kind="text"
                diff -u --label "$base_day" --label "$day" \
                    "$WORK/old.md" "$WORK/new.md" >"$WORK/diff.raw" || true
                cap_diff "$WORK/diff.raw" "$WORK/diff.cut"
                {
                    diff_header "$title" "changed" "$base_day" "$day" "$url" "$cites"
                    printf '## Diff\n\n```diff\n'
                    cat "$WORK/diff.cut"
                    printf '```\n'
                } >"$out_dir/$file"
            fi
            ;;
        *)
            kind="unavailable"
            file=""
            ;;
    esac

    DIFF_KIND="$kind"
    DIFF_FILE="$file"
}

# Emit the whole interval. Never fails the caller over a single article: a
# missing body is reported as "unavailable", not as an error.
emit_diffs() {
    local affected="$1" day="$2" snap_dir="$3" base_dir="$4" out_root="$5"
    local out_dir rows base_day status url cites kind file
    local emitted=0 unavailable=0
    local -a slugs=() kinds=() files=() urls=()

    [[ -f "$affected" ]] || die "affected JSON not found: $affected"
    [[ -d "$snap_dir" ]] || die "snapshot not found: $snap_dir"
    [[ -f "$snap_dir/manifest.json" ]] \
        || die "snapshot has no manifest.json: $snap_dir"
    if [[ -z "$base_dir" ]]; then
        log "no baseline snapshot found; every article is recorded as unavailable"
        base_dir="$WORK/no-baseline"
        mkdir -p "$base_dir"
    fi

    base_day="$(snapshot_day "$base_dir")"
    BASE_LABEL=""
    [[ -f "$base_dir/manifest.json" ]] && BASE_LABEL="$(basename "$base_dir")"
    out_dir="$out_root/diffs/$day"
    mkdir -p "$out_dir"

    rows="$(jq -r '
        [ .rows[] ]
        | group_by(.url)
        | map({status: .[0].status, url: .[0].url,
               cites: ([ .[] | select(.file != null)
                         | "`\(.file):\(.line)`" ] | unique)})
        | sort_by(.url)
        | .[]
        | [.status, .url, (.cites | join(", "))] | @tsv' "$affected")"

    while IFS=$'\t' read -r status url cites; do
        [[ -n "$url" ]] || continue
        write_article_diff "$status" "$url" "$cites" "$base_dir" "$snap_dir" \
            "$base_day" "$day" "$out_dir"
        kind="$DIFF_KIND"
        file="$DIFF_FILE"
        if [[ "$kind" == "unavailable" ]]; then
            unavailable=$((unavailable + 1))
        else
            emitted=$((emitted + 1))
        fi
        urls+=("$url"); slugs+=("$(slug_of_url "$url")")
        kinds+=("$kind"); files+=("$file")
    done <<<"$rows"

    if [[ $JSON_OUT -eq 1 ]]; then
        jq -n --arg date "$day" --arg dir "diffs/$day" --arg base "$BASE_LABEL" \
            --argjson emitted "$emitted" --argjson unavailable "$unavailable" \
            --argjson urls "$(printf '%s\n' "${urls[@]}" | jq -R . | jq -s .)" \
            --argjson slugs "$(printf '%s\n' "${slugs[@]}" | jq -R . | jq -s .)" \
            --argjson kinds "$(printf '%s\n' "${kinds[@]}" | jq -R . | jq -s .)" \
            --argjson files "$(printf '%s\n' "${files[@]}" | jq -R . | jq -s .)" '
            {date: $date, dir: $dir, baseline: $base,
             emitted: $emitted, unavailable: $unavailable,
             articles: [ range(0; ($urls | length)) as $i
                         | {url: $urls[$i], slug: $slugs[$i],
                            kind: $kinds[$i], file: $files[$i]} ]}'
    else
        local i
        for ((i = 0; i < ${#slugs[@]}; i++)); do
            printf '%s\t%s\t%s\n' "${slugs[$i]}" "${kinds[$i]}" "${files[$i]}"
        done
        log "diffs: $emitted file(s), $unavailable unavailable, in ${out_dir#"$ROOT"/}"
    fi
}

# --- tree --------------------------------------------------------------------

CHANGES_REL=""

# Where the diff tree sits relative to the Markdown file that links into it.
changes_rel() {
    local from
    from="$(dirname "$OUT_FILE")"
    if have realpath; then
        # -m: the tree may not exist yet on a first render.
        realpath -m --relative-to="$from" "$CHANGES_DIR" 2>/dev/null \
            || printf '%s' "$CHANGES_DIR"
    else
        printf '%s' "$CHANGES_DIR"
    fi
}

# A completed snapshot directory by name, searched across every cache.
find_snapshot_named() {
    local name="$1" cache
    [[ -n "$name" ]] || return 1
    for cache in "${CACHES[@]}"; do
        if [[ -f "$cache/$name/manifest.json" ]]; then
            printf '%s' "$cache/$name"
            return 0
        fi
    done
    return 1
}

# The newest completed snapshot standing for a date, for a record that predates
# the baseline_snapshot field.
find_snapshot_on() {
    local day="$1" cache dir best=""
    [[ -n "$day" ]] || return 1
    for cache in "${CACHES[@]}"; do
        [[ -d "$cache" ]] || continue
        for dir in "$cache"/*/; do
            [[ -f "$dir/manifest.json" ]] || continue
            [[ "$(snapshot_day "$dir")" == "$day" ]] || continue
            best="${dir%/}"
        done
    done
    [[ -n "$best" ]] || return 1
    printf '%s' "$best"
}

# Regenerate one record's diffs from the snapshots, into OUT_STATE. Used when the
# live capture is gone (state lost, or an interval backfilled from manifests).
emit_record_diffs() {
    local record="$1" out_state="$2"
    local date snap base_snap base_date snap_dir base_dir affected
    date="$(jq -r '.date' <<<"$record")"
    snap="$(jq -r '.snapshot // ""' <<<"$record")"
    base_snap="$(jq -r '.baseline_snapshot // ""' <<<"$record")"
    base_date="$(jq -r '.baseline // ""' <<<"$record")"
    snap_dir="$(find_snapshot_named "$snap")" || return 1
    base_dir=""
    if [[ -n "$base_snap" ]]; then
        base_dir="$(find_snapshot_named "$base_snap")" || base_dir=""
    fi
    [[ -n "$base_dir" ]] || base_dir="$(find_snapshot_on "$base_date")" || base_dir=""

    affected="$WORK/affected.$date.json"
    printf '%s' "$record" | jq '{
        rows: [ .articles[] as $a
                | if (($a.citations // []) | length) == 0 then
                      {status: $a.status, url: $a.url, file: null, line: null}
                  else
                      (($a.citations // [])[]
                       | capture("^(?<f>.*):(?<l>[0-9]+)$")
                       | {status: $a.status, url: $a.url,
                          file: .f, line: (.l | tonumber)})
                  end ]}' >"$affected" || return 1

    emit_diffs "$affected" "$date" "$snap_dir" "$base_dir" "$out_state" \
        >/dev/null 2>&1
}

write_changes_readme() {
    local dest="$1"
    cat >"$dest" <<'EOF'
# KB change diffs

One file per article per reporting interval, rendered by
`scripts/gridpane-kb-history.sh` from the weekly KB report's ledger and the
snapshots it captured. [`KB-CHANGES.md`](../KB-CHANGES.md) is the index; this
directory is the evidence behind it.

Layout: `YYYY/MM/YYYY-MM-DD-<slug>.md`, named for the interval's report date and
the article's WordPress slug.

Each file opens with the title, the change status, the interval, the article URL
and the `file:line` that cites it, then the body its status calls for:

| Status | Body |
|---|---|
| `changed`, text moved | A unified diff of the extracted text, three lines of context, truncated at 64 KB |
| `changed`, hash only | A note that the extracted text is identical and only the rendered markup moved |
| `added` | The extracted size and the URL — never the article's text |
| `removed` | A note that the URL no longer resolves, with its last title |
| `title-only` | The before and after title |

The diff is over text extracted from the KB's REST feed, not the published
HTML, so code blocks and tables may reflow. Treat it as a reading aid: open the
article when a hunk is ambiguous, and never edit a citation from a hunk alone.

Nothing here is written by the scheduled job. Regenerate it from the repository
root with `scripts/gridpane-kb-history.sh --backfill`.
EOF
}

# Render the whole tree into DEST and, beside it, a map from "date|url" to the
# file this render produced. Backfills from the snapshots whenever the live
# capture or the record's own file list cannot supply a file.
render_changes() {
    local dest="$1" records record date dd url slug file src rel copied=0 tried
    records="$(records_json)"
    rm -rf "$dest"
    mkdir -p "$dest"
    write_changes_readme "$dest/README.md"
    : >"$WORK/diffmap.tsv"

    if [[ "$(printf '%s' "$records" | jq 'length')" -gt 0 ]]; then
        while IFS= read -r record; do
            date="$(jq -r '.date' <<<"$record")"
            dd="$(jq -r '.diff_dir // ""' <<<"$record")"
            tried=0
            while IFS=$'\t' read -r url slug; do
                [[ -n "$slug" ]] || continue
                file="$date-$slug.md"
                src=""
                if [[ -n "$dd" && -f "$STATE/$dd/$file" ]]; then
                    src="$STATE/$dd/$file"
                fi
                if [[ -z "$src" && "$tried" -eq 0 ]]; then
                    emit_record_diffs "$record" "$WORK/backfill" || true
                    tried=1
                fi
                if [[ -z "$src" && -f "$WORK/backfill/diffs/$date/$file" ]]; then
                    src="$WORK/backfill/diffs/$date/$file"
                fi
                [[ -n "$src" ]] || continue
                rel="${date:0:4}/${date:5:2}/$file"
                mkdir -p "$dest/${date:0:4}/${date:5:2}"
                cp "$src" "$dest/$rel"
                printf '%s|%s\t%s\n' "$date" "$url" "$rel" >>"$WORK/diffmap.tsv"
                copied=$((copied + 1))
            done < <(jq -r '
                .articles[]?
                | [.url, (.url | sub("/$"; "") | split("/") | last)] | @tsv' <<<"$record")
        done < <(printf '%s' "$records" | jq -c '.[]')
    fi

    jq -Rn '[ inputs | split("\t") | {(.[0]): .[1]} ] | add // {}' \
        <"$WORK/diffmap.tsv" >"$WORK/diffmap.json"
    log "changes: $copied diff file(s)"
}

# Make DEST match SRC. Only renderer-owned names are ever removed, and an empty
# month or year directory goes with them.
sync_changes() {
    local src="$1" dest="$2" rel base f d
    mkdir -p "$dest"
    while IFS= read -r rel; do
        mkdir -p "$dest/$(dirname "$rel")"
        cmp -s "$src/$rel" "$dest/$rel" || cp "$src/$rel" "$dest/$rel"
    done < <(cd "$src" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)

    for f in "$dest"/[0-9][0-9][0-9][0-9]/[0-9][0-9]/*.md; do
        [[ -f "$f" ]] || continue
        base="${f#"$dest"/}"
        if [[ ! -f "$src/$base" ]]; then
            rm -f "$f"
            log "removed stale ${f#"$ROOT"/}"
        fi
    done
    for d in "$dest"/[0-9][0-9][0-9][0-9]/[0-9][0-9]; do
        if [[ -d "$d" ]]; then rmdir "$d" 2>/dev/null || true; fi
    done
    for d in "$dest"/[0-9][0-9][0-9][0-9]; do
        if [[ -d "$d" ]]; then rmdir "$d" 2>/dev/null || true; fi
    done
    for f in "$dest"/*; do
        [[ -f "$f" ]] || continue
        if [[ "$(basename "$f")" != "README.md" ]]; then
            log "left alone (not renderer-owned): ${f#"$ROOT"/}"
        fi
    done
    return 0
}

# Compare the rendered tree with what is on disk. Returns 0 when they match.
check_changes() {
    local exp="$1" rel base f bad=0
    while IFS= read -r rel; do
        if [[ ! -f "$CHANGES_DIR/$rel" ]]; then
            log "missing: ${CHANGES_DIR#"$ROOT"/}/$rel"
            bad=1
        elif ! cmp -s "$exp/$rel" "$CHANGES_DIR/$rel"; then
            log "stale: ${CHANGES_DIR#"$ROOT"/}/$rel"
            bad=1
        fi
    done < <(cd "$exp" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)

    for f in "$CHANGES_DIR"/[0-9][0-9][0-9][0-9]/[0-9][0-9]/*.md; do
        [[ -f "$f" ]] || continue
        base="${f#"$CHANGES_DIR"/}"
        if [[ ! -f "$exp/$base" ]]; then
            log "extra: ${f#"$ROOT"/}"
            bad=1
        fi
    done
    return "$bad"
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
        [ .[] | select(type == "object" and (.schema // 0) >= 1
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
    local dest="$1" records labels diffs
    CHANGES_REL="$(changes_rel)"
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
    diffs="$(cat "$WORK/diffmap.json")"
    printf '%s' "$records" | jq -r --argjson labels "$labels" --arg prefix "$CHANGES_REL" \
        --argjson diffs "$diffs" '
        def status_label: if . == "title" then "title-only" else . end;
        def status_rank: {"added": 0, "removed": 1, "changed": 2, "title": 3}[.] // 9;
        def bullet($backfilled; $date; $prefix):
            "- \(.status | status_label) — [\(if .title == "" then .url else .title end)](\(.url))"
            + ( ($diffs["\($date)|\(.url)"] // "") as $d
                | if $d != "" then " · [diff](\($prefix)/\($d))"
                  elif $backfilled then ""
                  else " · diff unavailable" end )
            + (if $backfilled then ""
               elif (.citations | length) > 0 then
                   " — cited by " + ([.citations[] | "`\(.)`"] | join(", "))
               else " — uncited" end);
        def block($prefix):
            . as $record
            | (.result == "backfilled") as $backfilled
            | "**\(.date)** · snapshot `\(.snapshot)` · baseline `\(.baseline)` · \(.result)\n"
            + "\(.counts.added // 0) added · \(.counts.removed // 0) removed"
            + " · \(.counts.changed // 0) changed · \(.counts.title_only // 0) title-only\n"
            + (if $backfilled then
                   "Backfilled from the snapshot manifests; citations were not recorded.\n"
               else "" end)
            + (if (.articles | length) == 0 then "- no article changes"
               else ([.articles[]] | sort_by((.status | status_rank), .title)
                     | map(bullet($backfilled; $record.date; $prefix)) | join("\n")) end);
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
                        + ([ $all[] | select(.date[0:7] == $m) | block($prefix) ] | join("\n\n"))
                    ] | join("\n"))
             ] | join("\n"))
          )
    ' >"$dest"
}

# --- run ---------------------------------------------------------------------

if [[ $EMIT_DIFFS -eq 1 ]]; then
    [[ -x "$SCRAPER" || -r "$SCRAPER" ]] \
        || die "scraper not found: ${SCRAPER#"$ROOT"/} (pass --scraper)"
    if [[ -z "$BASE_SNAP" ]]; then
        BASE_SNAP="$(resolve_baseline_snapshot "$BASE_MANIFEST")" || BASE_SNAP=""
    fi
    [[ "$SNAP_DIR" = /* ]] || SNAP_DIR="$ROOT/$SNAP_DIR"
    if [[ -n "$BASE_SNAP" ]]; then
        [[ "$BASE_SNAP" = /* ]] || BASE_SNAP="$ROOT/$BASE_SNAP"
        [[ -d "$BASE_SNAP" ]] || die "baseline snapshot not found: $BASE_SNAP"
    fi
    emit_diffs "$AFFECTED" "$DATE" "$SNAP_DIR" "$BASE_SNAP" "$STATE"
    exit 0
fi

if [[ $BACKFILL -eq 1 ]]; then
    backfill_ledger
fi

[[ -f "$LEDGER" ]] || die "ledger not found: ${LEDGER#"$ROOT"/} (run the weekly report, or --backfill)"

TMP_MD="$WORK/history.md"

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

TMP_CHANGES="$WORK/changes"
render_changes "$TMP_CHANGES"
render_markdown "$TMP_MD"

if [[ $CHECK -eq 1 ]]; then
    bad=0
    if [[ ! -f "$OUT_FILE" ]]; then
        log "missing: ${OUT_FILE#"$ROOT"/}"
        bad=1
    elif ! cmp -s "$TMP_MD" "$OUT_FILE"; then
        log "stale: ${OUT_FILE#"$ROOT"/}"
        bad=1
    fi
    check_changes "$TMP_CHANGES" || bad=1
    if [[ $bad -eq 0 ]]; then
        log "current: ${OUT_FILE#"$ROOT"/} and ${CHANGES_DIR#"$ROOT"/}/ match the ledger"
        exit 0
    fi
    log "stale: run ${SCRIPT_NAME} --backfill"
    exit 3
fi

if [[ $TO_STDOUT -eq 1 ]]; then
    cat "$TMP_MD"
    exit 0
fi

mkdir -p "$(dirname "$OUT_FILE")"
mv "$TMP_MD" "$OUT_FILE"
sync_changes "$TMP_CHANGES" "$CHANGES_DIR"
log "wrote ${OUT_FILE#"$ROOT"/} and ${CHANGES_DIR#"$ROOT"/}/"
