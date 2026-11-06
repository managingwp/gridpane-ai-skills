#!/usr/bin/env bash
#
# gridpane-kb-docs.sh - scrape, inspect and manage the GridPane KB cache.
#
# Commands:
#
#   status    What is ingested into the skills, what is cached, what drifted.
#             Reads local state only (no network), so it is safe to run anytime.
#   check     One request: exit 0 when nothing changed since the last full run,
#             3 when something did. Intended for automation.
#   refresh   Probe, index the REST feed into a new dated snapshot (10 s between
#             requests, count/total/shape guards), diff it against the previous
#             snapshot, and publish the manifest when its content changed.
#   audit     Are the citations sound? Four offline checks over the committed
#             manifest and skills/**/*.md (unknown, uncited-new, stale,
#             coverage), plus an opt-in --probe for the unknown URLs only.
#
# Wraps skills/gridpane-tooling/scripts/scrape-docs.sh: no URL, snapshot or
# category logic is duplicated here. Raw pages, extracted text and snapshots stay
# in the gitignored cache; the manifest is the only artifact that reaches git.
#
# Definitions used by status:
#   ingested    articles in the committed manifest
#               (skills/gridpane-tooling/references/docs-manifest.json)
#   cached      articles in the newest completed snapshot under
#               out/gridpane-docs-cache/<YYYY-MM-DD>[-N]/
#   extracted   .md files in that snapshot
#   drift       differences between the committed manifest and that snapshot
#
# Exit status: 0 success, 3 check found changes or audit found an unsound
# citation, 2 usage error, 1 failure.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRAPER="$ROOT/skills/gridpane-tooling/scripts/scrape-docs.sh"
MANIFEST="$ROOT/skills/gridpane-tooling/references/docs-manifest.json"
CACHE="$ROOT/out/gridpane-docs-cache"
SKILLS_DIR="$ROOT/skills"
UA="gridpane-ai-skills/audit (+https://github.com/managingwp/gridpane-ai-skills)"

AUDIT_TMP=""
cleanup_audit_tmp() {
    if [[ -n "$AUDIT_TMP" ]]; then
        rm -rf "$AUDIT_TMP"
    fi
    return 0
}
trap cleanup_audit_tmp EXIT

COMMAND=""
OFFLINE=0
REMOTE=0
FORCE=0
JSON_OUT=0
FILTER=""
LIMIT=""
SLUG=""
ALL=0
FORMAT=""
KEEP=""
YES=0
PROBE=0
PROBE_FILE=""
ALLOW_FAST=0
IGNORE=()
PASSTHRU=()
POSITIONAL=()

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} <command> [options]

Scrape, inspect and manage the GridPane Knowledge Base cache.

Commands:
  status [--json] [--remote]
                      What is ingested, cached and extracted, plus the snapshot
                      list and drift. Local only unless --remote adds one probe
  check               One request: exit 0 unchanged, 3 changed
  refresh             Probe, index a new snapshot, diff, publish the manifest
  list                Articles in the newest snapshot, newest first
  search QUERY        One-request lookup against the live KB
  diff [PREV]         What changed between two snapshots
  affected [PREV]     Which skill files cite an article that changed between snapshots
  audit               Are the citations sound? unknown, uncited-new, stale and
                      coverage, offline; --probe adds moved/down for unknown URLs
  extract             Cached article body as text or markdown
  prune               Remove old snapshots (dry run unless --yes)
  help                Show this help and exit

Options:
  --offline           refresh: skip the probe and rebuild from the newest snapshot
  --force             refresh: pass --force to the indexer (accept a count drop)
  --json              Print JSON instead of plain lines (status, check, refresh,
                      list, search, diff, affected, audit, prune)
  --filter TEXT       list: keep rows whose slug or title contains TEXT
  --limit N           list/search: at most N rows (list default 20)
  --slug SLUG         extract: the article to convert
  --all               extract: convert every article in the snapshot;
                      affected: also list changed articles no skill cites
  --skills DIR        affected/audit: scan this tree for citations (default skills/)
  --format text|markdown  extract: output format (default markdown)
  --keep N            prune: snapshots to keep, newest first (default 5)
  --yes               prune: actually delete; without it nothing is removed
  --manifest FILE     refresh/audit: use this manifest instead of the committed one
  --probe             audit: request the unknown URLs only, 10 s apart, and
                      report redirects (moved) and 404/410 (down)
  --probe-file FILE   audit: read saved {url: {status, location}} responses
                      instead of fetching (fixtures only)
  --ignore URL        audit: accept this URL; repeatable. It stays counted as a
                      citation but is left out of every finding
  -h, --help          Show this help and exit

Passed through to scrape-docs.sh: --base URL, --cache DIR, --snapshot DIR,
--partial, --probe-json FILE, --allow-fast (fixtures only). The 10 s delay is the
scraper's default and cannot be lowered for a live run without --allow-fast.
EOF
}

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

if [[ $# -gt 0 && "$1" != -* ]]; then
    COMMAND="$1"
    shift
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --offline)    OFFLINE=1; shift ;;
        --remote)     REMOTE=1; shift ;;
        --force)      FORCE=1; shift ;;
        --json)       JSON_OUT=1; shift ;;
        --filter)     FILTER="${2:?--filter needs a value}"; shift 2 ;;
        --filter=*)   FILTER="${1#--filter=}"; shift ;;
        --limit)      LIMIT="${2:?--limit needs a value}"; shift 2 ;;
        --limit=*)    LIMIT="${1#--limit=}"; shift ;;
        --slug)       SLUG="${2:?--slug needs a value}"; shift 2 ;;
        --slug=*)     SLUG="${1#--slug=}"; shift ;;
        --all)        ALL=1; shift ;;
        --format)     FORMAT="${2:?--format needs a value}"; shift 2 ;;
        --format=*)   FORMAT="${1#--format=}"; shift ;;
        --keep)       KEEP="${2:?--keep needs a value}"; shift 2 ;;
        --keep=*)     KEEP="${1#--keep=}"; shift ;;
        --yes)        YES=1; shift ;;
        --manifest)   MANIFEST="${2:?--manifest needs a value}"; shift 2 ;;
        --manifest=*) MANIFEST="${1#--manifest=}"; shift ;;
        --skills)     SKILLS_DIR="${2:?--skills needs a value}"; shift 2 ;;
        --skills=*)   SKILLS_DIR="${1#--skills=}"; shift ;;
        --probe)      PROBE=1; shift ;;
        --probe-file) PROBE_FILE="${2:?--probe-file needs a value}"; shift 2 ;;
        --probe-file=*) PROBE_FILE="${1#--probe-file=}"; shift ;;
        --ignore)     IGNORE+=("${2:?--ignore needs a value}"); shift 2 ;;
        --ignore=*)   IGNORE+=("${1#--ignore=}"); shift ;;
        -h|--help)    usage; exit 0 ;;
        --base|--cache|--snapshot|--partial|--probe-json)
            PASSTHRU+=("$1"); shift
            [[ $# -gt 0 ]] || die "$1 needs a value"
            PASSTHRU+=("$1"); shift ;;
        --base=*|--cache=*|--snapshot=*|--probe-json=*)
            PASSTHRU+=("$1"); shift ;;
        --allow-fast) ALLOW_FAST=1; PASSTHRU+=("$1"); shift ;;
        -*) log "error: unknown option: $1"; usage >&2; exit 2 ;;
        *)  POSITIONAL+=("$1"); shift ;;
    esac
done

[[ -x "$SCRAPER" ]] || die "scraper not found or not executable: $SCRAPER"
have jq || die "jq is required"

if [[ ${#PASSTHRU[@]} -gt 0 ]]; then
    for ((i = 0; i < ${#PASSTHRU[@]}; i++)); do
        case "${PASSTHRU[$i]}" in
            --cache) CACHE="${PASSTHRU[$((i + 1))]}" ;;
            --cache=*) CACHE="${PASSTHRU[$i]#--cache=}" ;;
        esac
    done
fi

latest_snapshot() {
    local name="" dir=""
    if [[ -L "$CACHE/latest" ]]; then
        name="$(readlink "$CACHE/latest")"
    elif [[ -f "$CACHE/latest" ]]; then
        name="$(head -1 "$CACHE/latest")"
    fi
    if [[ -n "$name" && -f "$CACHE/$name/manifest.json" ]]; then
        printf '%s' "$CACHE/$name"
        return 0
    fi
    # No usable pointer: fall back to the newest completed snapshot.
    dir="$(snapshot_names | tail -1)"
    [[ -n "$dir" ]] || return 1
    printf '%s' "$CACHE/$dir"
}

snapshot_names() {
    [[ -d "$CACHE" ]] || return 0
    find "$CACHE" -maxdepth 1 -type d -name '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]*' \
        2>/dev/null | sort | while IFS= read -r d; do
        [[ -f "$d/manifest.json" ]] && basename "$d"
    done
}

probe_line() {
    local out
    if out="$("$SCRAPER" --probe --since-last "${PASSTHRU[@]}" 2>/dev/null)"; then
        printf '%s' "$out"
        return 0
    fi
    # No cursor yet (first run) - treat it as "changes available".
    printf '%s' "no-cursor"
}

drift_counts() {
    jq -n --slurpfile a "$1" --slurpfile b "$2" '
        ($a[0].entries | map({key: .url, value: .}) | from_entries) as $am
        | ($b[0].entries | map({key: .url, value: .}) | from_entries) as $bm
        | {
            added: ([$bm | keys[] | select($am[.] == null)] | length),
            removed: ([$am | keys[] | select($bm[.] == null)] | length),
            changed: ([$bm | keys[] | select($am[.] != null
                       and $am[.].sha256 != $bm[.].sha256)] | length),
            title_changed: ([$bm | keys[] | select($am[.] != null
                       and $am[.].sha256 == $bm[.].sha256
                       and $am[.].title != $bm[.].title)] | length)
          }'
}

# --- status -----------------------------------------------------------------

# name<TAB>articles<TAB>bytes<TAB>extracted, newest first, completed snapshots
# only (a directory without manifest.json is an aborted run).
snapshot_tsv() {
    local name
    snapshot_names | sort -r | while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        printf '%s\t%s\t%s\t%s\n' "$name" \
            "$(jq -r '.count // 0' "$CACHE/$name/manifest.json")" \
            "$(du -sb "$CACHE/$name" 2>/dev/null | cut -f1)" \
            "$(find "$CACHE/$name" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
    done
}

# True when $1 sorts strictly before $2 (ISO-8601 timestamps compare
# lexicographically). Equal values are not older.
is_older() {
    [[ "$1" != "$2" ]] \
        && [[ "$(printf '%s\n%s\n' "$1" "$2" | LC_ALL=C sort | head -1)" == "$1" ]]
}

human_size() {
    awk -v b="${1:-0}" 'BEGIN {
        if (b >= 1073741824) printf "%.1fG", b / 1073741824
        else if (b >= 1048576) printf "%.1fM", b / 1048576
        else if (b >= 1024) printf "%.0fK", b / 1024
        else printf "%dB", b
    }'
}

# One probe request plus the local cursor decides up to date / newer / unknown.
remote_state() {
    local line modified slug cursor
    if ! line="$("$SCRAPER" --probe "${PASSTHRU[@]}" 2>/dev/null)"; then
        printf 'unreachable\t\t\n'
        return 0
    fi
    modified="${line%%$'\t'*}"
    slug="${line#*$'\t'}"
    cursor="$(jq -r '.fetched_at // empty' "$CACHE/last-run.json" 2>/dev/null || true)"
    if [[ -z "$cursor" ]]; then
        printf 'unknown\t%s\t%s\n' "$modified" "$slug"
    elif is_older "${cursor%Z}" "${modified%Z}"; then
        printf 'newer\t%s\t%s\n' "$modified" "$slug"
    else
        printf 'up-to-date\t%s\t%s\n' "$modified" "$slug"
    fi
}

cmd_status() {
    local ingested="-" schema="?" fetched="-" snap="" cached="-" files="-"
    local bytes="0" extracted="-" drift="" tsv="" snap_count=0
    local newest_mod="-" newest_slug="-"
    local rstate="" rmod="" rslug=""

    if [[ -f "$MANIFEST" ]]; then
        ingested="$(jq -r '.count // "-"' "$MANIFEST" 2>/dev/null || printf '-')"
        schema="$(jq -r '.schema // "?"' "$MANIFEST" 2>/dev/null || printf '?')"
        fetched="$(jq -r '.fetched_at // "-"' "$MANIFEST" 2>/dev/null || printf '-')"
    fi

    snap="$(latest_snapshot || true)"
    if [[ -n "$snap" ]]; then
        cached="$(jq -r '.count // 0' "$snap/manifest.json")"
        files="$(find "$snap" -type f | wc -l | tr -d ' ')"
        bytes="$(du -sb "$snap" 2>/dev/null | cut -f1)"
        extracted="$(find "$snap" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
        newest_mod="$(jq -r '[.entries[] | select(.modified != "")]
                      | max_by(.modified) | .modified // "-"' "$snap/manifest.json")"
        newest_slug="$(jq -r '[.entries[] | select(.modified != "")]
                      | max_by(.modified) | (.url // "-")
                      | sub(".*/kb/"; "") | sub("/$"; "")' "$snap/manifest.json")"
        if [[ -f "$MANIFEST" ]]; then
            drift="$(drift_counts "$MANIFEST" "$snap/manifest.json")"
        fi
    fi

    tsv="$(snapshot_tsv)"
    snap_count="$(printf '%s\n' "$tsv" | grep -c '^' || true)"

    if [[ "$REMOTE" -eq 1 ]]; then
        IFS=$'\t' read -r rstate rmod rslug < <(remote_state)
    fi

    if [[ "$JSON_OUT" -eq 1 ]]; then
        jq -n \
            --arg path "${MANIFEST#"$ROOT"/}" \
            --arg ingested "$ingested" --arg schema "$schema" --arg fetched "$fetched" \
            --arg snapname "$([[ -n "$snap" ]] && basename "$snap" || true)" \
            --arg cached "$cached" --arg files "$files" --arg bytes "$bytes" \
            --arg extracted "$extracted" --arg drift "$drift" --arg tsv "$tsv" \
            --arg newest_mod "$newest_mod" --arg newest_slug "$newest_slug" \
            --arg rstate "$rstate" --arg rmod "$rmod" --arg rslug "$rslug" '
            def num: (try (. | tonumber) catch null);
            {
              ingested: {
                path: $path,
                count: ($ingested | num),
                schema: ($schema | num),
                fetched_at: (if $fetched == "-" then null else $fetched end)
              },
              cached: (if $snapname == "" then null else {
                snapshot: $snapname,
                count: ($cached | num),
                files: ($files | num),
                size_bytes: ($bytes | num)
              } end),
              extracted: { count: ($extracted | num) },
              drift: (if $drift == "" then null else ($drift | fromjson) end),
              newest: (if $snapname == "" then null else {
                slug: $newest_slug, modified: $newest_mod
              } end),
              snapshots: ($tsv | split("\n") | map(select(length > 0) | split("\t") | {
                name: .[0], count: (.[1] | tonumber),
                size_bytes: (.[2] | tonumber), extracted: (.[3] | tonumber)
              })),
              remote: (if $rstate == "" then null else {
                state: $rstate,
                modified: (if $rmod == "" then null else $rmod end),
                slug: (if $rslug == "" then null else $rslug end)
              } end)
            }'
        return 0
    fi

    printf 'KB status\n'
    printf '  %-10s %4s articles  %s\n' "ingested" "$ingested" \
        "${MANIFEST#"$ROOT"/} (schema $schema, fetched $fetched)"
    if [[ -n "$snap" ]]; then
        printf '  %-10s %4s articles  snapshot %s (%s files, %s)\n' \
            "cached" "$cached" "$(basename "$snap")" "$files" "$(human_size "$bytes")"
        printf '  %-10s %4s articles  .md in snapshot %s\n' \
            "extracted" "$extracted" "$(basename "$snap")"
    else
        printf '  %-10s %4s articles  no completed snapshot\n' "cached" "-"
        printf '  %-10s %4s articles  -\n' "extracted" "-"
    fi
    if [[ -n "$drift" ]]; then
        printf '  %-10s %s added, %s removed, %s changed, %s title-only vs ingested\n' \
            "drift" "$(jq -r '.added' <<<"$drift")" "$(jq -r '.removed' <<<"$drift")" \
            "$(jq -r '.changed' <<<"$drift")" "$(jq -r '.title_changed' <<<"$drift")"
    else
        printf '  %-10s -  (need both a manifest and a snapshot)\n' "drift"
    fi
    if [[ -n "$snap" ]]; then
        printf '  %-10s %s  %s\n' "newest" "$newest_mod" "$newest_slug"
    fi
    if [[ "$REMOTE" -eq 1 ]]; then
        case "$rstate" in
            up-to-date) printf '  %-10s %s  %s  (up to date)\n' "remote" "$rmod" "$rslug" ;;
            newer)      printf '  %-10s %s  %s  (newer than the last run)\n' "remote" "$rmod" "$rslug" ;;
            unreachable) printf '  %-10s %s\n' "remote" "unreachable" ;;
            *)          printf '  %-10s %s  %s  (no cursor; run: %s refresh)\n' \
                            "remote" "$rmod" "$rslug" "$SCRIPT_NAME" ;;
        esac
    fi

    printf '  %-10s %4s\n' "snapshots" "$snap_count"
    local shown=0 name count sbytes sextra
    while IFS=$'\t' read -r name count sbytes sextra; do
        [[ -n "$name" ]] || continue
        if [[ "$shown" -ge 10 ]]; then
            printf '    (+%s older)\n' "$((snap_count - 10))"
            break
        fi
        printf '    %-14s %4s articles  %6s  %s extracted\n' \
            "$name" "$count" "$(human_size "$sbytes")" "$sextra"
        shown=$((shown + 1))
    done <<<"$tsv"

    if [[ ! -f "$MANIFEST" ]]; then
        log "hint: no committed manifest yet; run: ${SCRIPT_NAME} refresh"
    fi
    if [[ -z "$snap" ]]; then
        log "hint: no cached snapshot yet; run: ${SCRIPT_NAME} refresh"
    fi
    if [[ -n "$drift" ]] && [[ "$(jq -r '[.added,.removed,.changed,.title_changed] | add' <<<"$drift")" -gt 0 ]]; then
        log "warn: unpublished changes between the manifest and the newest snapshot; run: ${SCRIPT_NAME} refresh"
    fi
    if [[ -n "$snap" && -f "$MANIFEST" ]] \
        && is_older "$fetched" "$(jq -r '.fetched_at // ""' "$snap/manifest.json")"; then
        log "warn: the committed manifest is older than snapshot $(basename "$snap")"
    fi
}

# --- check ------------------------------------------------------------------

cmd_check() {
    local line
    [[ "$OFFLINE" -eq 0 ]] || die "check and --offline are mutually exclusive"

    line="$(probe_line)"
    if [[ "$line" == no-cursor ]]; then
        if [[ "$JSON_OUT" -eq 1 ]]; then
            printf '{"status":"no-cursor","changed":true}\n'
        else
            printf 'no previous run recorded; the first full refresh will index everything\n'
        fi
        exit 3
    fi
    if [[ "$line" == no\ changes* ]]; then
        if [[ "$JSON_OUT" -eq 1 ]]; then
            printf '{"status":"unchanged","changed":false}\n'
        else
            printf '%s\n' "$line"
        fi
        exit 0
    fi
    if [[ "$JSON_OUT" -eq 1 ]]; then
        jq -n --arg line "$line" \
            '{status:"changed", changed:true, newest: ($line | split("\t") | .[0]), slug: ($line | split("\t") | .[1])}'
    else
        printf 'changes available: %s\n' "$line"
    fi
    exit 3
}

# --- refresh ----------------------------------------------------------------

cmd_refresh() {
    local line snapshot diff_out counts changed candidate rel_snapshot

    if [[ "$OFFLINE" -eq 0 ]]; then
        line="$(probe_line)"
        if [[ "$line" == no\ changes* ]]; then
            if [[ "$JSON_OUT" -eq 1 ]]; then
                jq -n --arg msg "$line" '{status:"unchanged", changed:false, message:$msg}'
            else
                printf '%s\n' "$line"
            fi
            exit 0
        fi
        if [[ "$line" == no-cursor ]]; then
            log "no previous run recorded; indexing the full feed"
        else
            log "changes available: $line"
        fi
    fi

    local -a ARGS=()
    [[ "$FORCE" -eq 1 ]] && ARGS+=(--force)
    [[ "$OFFLINE" -eq 1 ]] && ARGS+=(--offline)
    if [[ ${#PASSTHRU[@]} -gt 0 ]]; then
        ARGS+=("${PASSTHRU[@]}")
    fi

    "$SCRAPER" "${ARGS[@]}" >/dev/null || die "index failed; the committed manifest was not touched"

    snapshot="$(latest_snapshot)" || die "no completed snapshot appeared after the run"

    diff_out="$(cd "$ROOT" && "$SCRAPER" --diff --json "${ARGS[@]}" 2>/dev/null || true)"
    counts="$(jq -c '.counts' <<<"$diff_out" 2>/dev/null || true)"
    if [[ -z "$counts" ]]; then
        counts='{"added":0,"removed":0,"changed":0,"title_changed":0}'
    fi

    changed=0
    candidate="$(mktemp)"
    if [[ -f "$MANIFEST" ]]; then
        # Keep an entry's fetched_at when its content did not change, so the
        # committed manifest only moves where the KB did.
        jq -n --slurpfile o "$MANIFEST" --slurpfile n "$snapshot/manifest.json" '
            ($o[0].entries // [] | map({key: .url, value: .}) | from_entries) as $old
            | $n[0]
            | .entries |= map(
                if ($old[.url] != null and $old[.url].sha256 == .sha256
                    and $old[.url].title == .title)
                then .fetched_at = $old[.url].fetched_at
                else . end)' > "$candidate"
    else
        cp "$snapshot/manifest.json" "$candidate"
    fi

    if [[ -f "$MANIFEST" ]] && cmp -s "$candidate" "$MANIFEST"; then
        rm -f "$candidate"
    else
        mv "$candidate" "$MANIFEST"
        changed=1
    fi

    rel_snapshot="${snapshot#"$ROOT"/}"
    if [[ "$JSON_OUT" -eq 1 ]]; then
        jq -n --arg snapshot "$rel_snapshot" --argjson counts "$counts" \
            --argjson changed "$changed" \
            '{status: (if $changed == 1 then "published" else "unchanged" end),
              snapshot: $snapshot, changes: $counts,
              manifest_updated: ($changed == 1)}'
    else
        printf 'snapshot: %s\n' "$rel_snapshot"
        printf 'changes: %s added, %s removed, %s changed, %s title-only\n' \
            "$(jq -r '.added // 0' <<<"$counts")" "$(jq -r '.removed // 0' <<<"$counts")" \
            "$(jq -r '.changed // 0' <<<"$counts")" "$(jq -r '.title_changed // 0' <<<"$counts")"
        if [[ "$changed" -eq 1 ]]; then
            printf 'manifest: updated %s\n' "${MANIFEST#"$ROOT"/}"
        else
            printf 'manifest: unchanged\n'
        fi
    fi
}

# --- list -------------------------------------------------------------------

cmd_list() {
    local snap="${1:-}" limit="${LIMIT:-20}" entries json

    [[ "$limit" =~ ^[0-9]+$ ]] || die "--limit must be a number"
    snap="$(latest_snapshot)" || die "no cached snapshot; run: ${SCRIPT_NAME} refresh"

    entries="$(jq -r --arg f "$FILTER" --argjson n "$limit" '
        [ .entries[]
          | select($f == ""
                   or ((.url | ascii_downcase) | contains($f | ascii_downcase))
                   or ((.title | ascii_downcase) | contains($f | ascii_downcase))) ]
        | sort_by(.url) | .[0:$n]
        | .[]
        | [ (.url | sub(".*/kb/"; "") | sub("/$"; "")), .modified, .url, .title ]
        | @tsv' "$snap/manifest.json")"

    if [[ "$JSON_OUT" -eq 1 ]]; then
        json="$(jq -n --arg snapshot "$(basename "$snap")" --arg filter "$FILTER" \
            --argjson limit "$limit" --arg tsv "$entries" '
            ($tsv | split("\n") | map(select(length > 0) | split("\t") | {
                slug: .[0], modified: .[1], url: .[2], title: .[3]
            })) as $rows
            | {snapshot: $snapshot, filter: $filter, limit: $limit,
               count: ($rows | length), entries: $rows}')"
        printf '%s\n' "$json"
    else
        printf '%s\n' "$entries"
    fi
}

# --- search -----------------------------------------------------------------

cmd_search() {
    local query="${POSITIONAL[0]:-}"
    local -a args=(--search "$query")

    [[ -n "$query" ]] || die "search needs a query"
    [[ -n "$LIMIT" ]] && args+=(--limit "$LIMIT")
    [[ "$JSON_OUT" -eq 1 ]] && args+=(--json)
    "$SCRAPER" "${args[@]}" "${PASSTHRU[@]}"
}

# --- diff -------------------------------------------------------------------

cmd_diff() {
    local -a args=(--diff)

    [[ -n "${POSITIONAL[0]:-}" ]] && args+=("${POSITIONAL[0]}")
    [[ "$JSON_OUT" -eq 1 ]] && args+=(--json)
    (cd "$ROOT" && "$SCRAPER" "${args[@]}" "${PASSTHRU[@]}")
}

# --- affected ---------------------------------------------------------------

# The citation map: every KB article URL the skills cite, as url<TAB>file<TAB>line.
# Computed at run time against the working tree so it cannot go stale the way a
# committed index would. Fenced code blocks are skipped: a URL inside an example
# is an illustration, not a citation, and would otherwise report as dead.
citation_map() {
    ( cd "$ROOT" && find "$SKILLS_DIR" -type f -name '*.md' -exec awk '
        BEGIN { PREFIX = "https://gridpane.com/kb/" }
        FNR == 1 { infence = 0; fchar = ""; flen = 0 }
        {
            probe = $0
            sub(/^[ \t]+/, "", probe)
            if (probe ~ /^(```|~~~)/) {
                c = substr(probe, 1, 1)
                n = 0
                while (substr(probe, n + 1, 1) == c) n++
                if (infence) {
                    if (c == fchar && n >= flen) { infence = 0; fchar = ""; flen = 0 }
                } else {
                    infence = 1; fchar = c; flen = n
                }
                next
            }
            if (infence) next

            rest = $0
            while ((p = index(rest, PREFIX)) > 0) {
                rest = substr(rest, p + length(PREFIX))
                body = ""
                while (length(rest) > 0) {
                    ch = substr(rest, 1, 1)
                    if (ch ~ /[A-Za-z0-9._-]/) { body = body ch; rest = substr(rest, 2) }
                    else break
                }
                if (body != "") printf "%s%s\t%s\t%s\n", PREFIX, body, FILENAME, FNR
            }
        }' {} + 2>/dev/null || true )
}

# Join the snapshot diff to the citation map: the answer to "which skill files
# does this KB change actually touch?". Read-only, offline, no writes.
cmd_affected() {
    local prev="" curr="" changed="" cites="" rows=""
    local changed_count=0 cited=0 references=0 files=0
    local -a names=()

    while IFS= read -r n; do
        [[ -n "$n" ]] && names+=("$n")
    done < <(snapshot_names | sort -r)
    if [[ ${#names[@]} -eq 0 ]]; then
        die "no completed snapshots in ${CACHE#"$ROOT"/}; run: scripts/gridpane-kb-docs.sh refresh"
    fi

    curr="${names[0]}"
    if [[ -n "${POSITIONAL[0]:-}" ]]; then
        prev="${POSITIONAL[0]}"
        [[ -f "$CACHE/$prev/manifest.json" ]] || die "unknown snapshot: $prev"
    else
        [[ ${#names[@]} -ge 2 ]] \
            || die "one snapshot only ($curr); name the earlier one: affected PREV"
        prev="${names[1]}"
    fi

    # The same change set `diff` reports: added, changed (body hash), removed,
    # and title-only. A `modified` timestamp edit alone is not a change.
    changed="$(jq -r -n --slurpfile a "$CACHE/$prev/manifest.json" \
        --slurpfile b "$CACHE/$curr/manifest.json" '
        ($a[0].entries | map({key: .url, value: .}) | from_entries) as $am
        | ($b[0].entries | map({key: .url, value: .}) | from_entries) as $bm
        | ( [ $bm | keys[] | select($am[.] == null)
              | {status: "added", url: .} ]
          + [ $bm | keys[] | select($am[.] != null
              and $am[.].sha256 != $bm[.].sha256)
              | {status: "changed", url: .} ]
          + [ $am | keys[] | select($bm[.] == null)
              | {status: "removed", url: .} ]
          + [ $bm | keys[] | select($am[.] != null
              and $am[.].sha256 == $bm[.].sha256
              and $am[.].title != $bm[.].title)
              | {status: "title", url: .} ] )
        | .[]
        | [ .status, (.url | sub("/$"; "")) ] | @tsv')"

    cites="$(citation_map)"

    # One row per citing file:line; --all adds the changed articles no skill
    # cites, with `-` where a location would be.
    rows="$(awk -F'\t' -v all="$ALL" '
        NR == FNR {
            if (NF >= 3) { n[$1]++; f[$1, n[$1]] = $2; l[$1, n[$1]] = $3 }
            next
        }
        NF >= 2 {
            if (n[$2] > 0) {
                for (i = 1; i <= n[$2]; i++)
                    print $1 "\t" $2 "\t" f[$2, i] ":" l[$2, i]
            } else if (all == 1) {
                print $1 "\t" $2 "\t-"
            }
        }' <(printf '%s\n' "$cites") <(printf '%s\n' "$changed") \
        | LC_ALL=C sort -t$'\t' -k1,1 -k2,2 -k3,3)"

    changed_count="$(printf '%s\n' "$changed" \
        | awk -F'\t' 'NF >= 2 && !seen[$2]++ { c++ } END { print c + 0 }')"
    read -r cited references files <<<"$(printf '%s\n' "$rows" | awk -F'\t' '
        NF >= 3 && $3 != "-" {
            if (!u[$2]++) c++
            file = $3; sub(/:[0-9]+$/, "", file)
            if (!f[file]++) fl++
            r++
        }
        END { print c + 0, r + 0, fl + 0 }')"

    if [[ "$JSON_OUT" -eq 1 ]]; then
        jq -n --arg prev "$prev" --arg curr "$curr" \
            --argjson changed "$changed_count" --argjson cited "$cited" \
            --argjson references "$references" --argjson files "$files" \
            --arg tsv "$rows" '
            {prev: $prev, curr: $curr,
             counts: {changed: $changed, cited: $cited,
                      references: $references, files: $files},
             rows: ($tsv | split("\n") | map(select(length > 0))
                    | map(split("\t") | {
                        status: .[0], url: .[1],
                        file: (if .[2] == "-" then null
                               else (.[2] | sub(":[0-9]+$"; "")) end),
                        line: (if .[2] == "-" then null
                               else (.[2] | split(":") | .[-1] | tonumber) end)
                      }))}'
    elif [[ -n "$rows" ]]; then
        printf '%s\n' "$rows"
    fi

    log "$changed_count changed, $cited cited, $references references in $files files (${prev}..${curr})"
}

# --- audit ------------------------------------------------------------------

# The date a citing file was last committed, as YYYY-MM-DD. A fixture or an
# uncommitted file falls back to its `Last verified:` line; an empty result means
# the staleness check cannot speak about that file.
file_committed() {
    local file="$1" dir base d
    dir="$(dirname "$file")"
    base="$(basename "$file")"
    d="$(git -C "$dir" log -1 --format=%cs -- "$base" 2>/dev/null || true)"
    if [[ -z "$d" && -f "$file" ]]; then
        d="$(sed -nE 's/^Last verified: ([0-9]{4}-[0-9]{2}-[0-9]{2})$/\1/p' "$file" | head -1)"
    fi
    printf '%s' "$d"
}

# True when $1 is in --ignore, compared without a trailing slash.
is_ignored() {
    local u="${1%/}" i
    [[ ${#IGNORE[@]} -gt 0 ]] || return 1
    for i in "${IGNORE[@]}"; do
        [[ "${i%/}" == "$u" ]] && return 0
    done
    return 1
}

# One request for one URL: "code<TAB>location". --probe-file reads a saved map
# instead ({url: {status, location}}), which is how the offline test covers it.
probe_target() {
    local u="$1" out
    if [[ -n "$PROBE_FILE" ]]; then
        out="$(jq -r --arg u "$u" --arg s "$u/" '
            (.[$u] // .[$s] // empty)
            | "\(.status // 0)\t\(.location // "")"' "$PROBE_FILE")"
    elif ! out="$(curl -sS -o /dev/null -A "$UA" --max-time 30 \
            -w '%{http_code}\t%{redirect_url}' "${u%/}/" 2>/dev/null)"; then
        out=$'0\t'
    fi
    printf '%s\n' "$out"
}

# Are the citations sound? Four checks that need no network — unknown (a cited
# slug the manifest does not list), uncited-new (an article added between the
# last two snapshots that no skill cites), stale (the article was modified after
# the citing file was last committed) and coverage (distinct articles cited, per
# skill) — plus --probe, which requests the unknown URLs only. unknown, moved and
# down are unsound citations and exit 3; uncited-new and stale are advisory and
# leave the exit code alone.
cmd_audit() {
    local tmp manifest_path articles=0 cited=0 references=0 files=0
    local prev="" curr="" have_snapshots=0
    local n_unknown=0 n_uncited=0 n_stale=0 n_moved=0 n_down=0 findings=0
    local u f l m d
    local -a names=()
    local -A committed=()

    [[ -f "$MANIFEST" ]] || die "no manifest at ${MANIFEST#"$ROOT"/}; run: ${SCRIPT_NAME} refresh"
    [[ -z "$PROBE_FILE" || -f "$PROBE_FILE" ]] || die "probe fixture not found: $PROBE_FILE"

    tmp="$(mktemp -d)"
    AUDIT_TMP="$tmp"
    manifest_path="${MANIFEST#"$ROOT"/}"

    articles="$(jq -r '.entries | length' "$MANIFEST")"
    jq -r '.entries[]
        | [(.url | sub("/$"; "")), (.modified // ""), (.title // "")]
        | @tsv' "$MANIFEST" | LC_ALL=C sort > "$tmp/known"

    citation_map | LC_ALL=C sort -u > "$tmp/cites"

    read -r cited references files <<<"$(awk -F'\t' '
        NF >= 3 { if (!u[$1]++) c++; r++; if (!f[$2]++) fl++ }
        END { print c + 0, r + 0, fl + 0 }' "$tmp/cites")"

    # unknown: cited but absent from the manifest.
    awk -F'\t' 'NR == FNR { known[$1] = 1; next }
        NF >= 3 && !($1 in known) { print }' "$tmp/known" "$tmp/cites" \
        | LC_ALL=C sort -t$'\t' -k1,1 -k3,3 > "$tmp/unknown_all"
    : > "$tmp/unknown"
    while IFS=$'\t' read -r u f l; do
        [[ -n "$u" ]] || continue
        is_ignored "$u" && continue
        printf '%s\t%s\t%s\n' "$u" "$f" "$l" >> "$tmp/unknown"
    done < "$tmp/unknown_all"
    n_unknown="$(awk -F'\t' 'NF { if (!u[$1]++) c++ } END { print c + 0 }' "$tmp/unknown")"

    # uncited-new: an article added between the last two snapshots that no skill
    # cites. Needs two snapshots; with fewer the check cannot speak.
    while IFS= read -r u; do
        [[ -n "$u" ]] && names+=("$u")
    done < <(snapshot_names | sort -r)
    : > "$tmp/uncited"
    if [[ ${#names[@]} -ge 2 ]]; then
        curr="${names[0]}"
        prev="${names[1]}"
        have_snapshots=1
        jq -r -n --slurpfile a "$CACHE/$prev/manifest.json" \
            --slurpfile b "$CACHE/$curr/manifest.json" '
            ($a[0].entries | map(.url | sub("/$"; ""))) as $old
            | $b[0].entries[]
            | (.url | sub("/$"; "")) as $u
            | select(($old | index($u)) == null)
            | [$u, (.title // ""), (.modified // "")] | @tsv' > "$tmp/added"
        if [[ -s "$tmp/cites" ]]; then
            awk -F'\t' 'NR == FNR { cited[$1] = 1; next }
                NF >= 1 && !($1 in cited) { print }' "$tmp/cites" "$tmp/added" \
                > "$tmp/uncited_all"
        else
            cp "$tmp/added" "$tmp/uncited_all"
        fi
        while IFS=$'\t' read -r u f m; do
            [[ -n "$u" ]] || continue
            is_ignored "$u" && continue
            printf '%s\t%s\t%s\n' "$u" "$f" "$m" >> "$tmp/uncited"
        done < "$tmp/uncited_all"
    fi
    n_uncited="$(awk -F'\t' 'NF { c++ } END { print c + 0 }' "$tmp/uncited")"

    # stale: the article's modified date is later than the citing file's last
    # commit. Only articles the manifest knows; an unknown URL is a different
    # finding.
    : > "$tmp/stale"
    while IFS=$'\t' read -r u f l; do
        [[ -n "$u" ]] || continue
        is_ignored "$u" && continue
        m="$(awk -F'\t' -v u="$u" '$1 == u { print $2; exit }' "$tmp/known")"
        [[ -n "$m" ]] || continue
        if [[ -z "${committed[$f]:-}" ]]; then
            committed["$f"]="$(file_committed "$f")"
        fi
        d="${committed[$f]}"
        [[ -n "$d" ]] || continue
        if is_older "$d" "${m:0:10}"; then
            printf '%s\t%s\t%s\t%s\t%s\n' "$u" "${m:0:10}" "$f" "$l" "$d" \
                >> "$tmp/stale"
        fi
    done < "$tmp/cites"
    n_stale="$(awk -F'\t' 'NF { c++ } END { print c + 0 }' "$tmp/stale")"

    # coverage: distinct articles cited, per skill directory.
    local skills_abs="$SKILLS_DIR" skills_rel="$SKILLS_DIR"
    [[ "$skills_abs" = /* ]] || skills_abs="$ROOT/$skills_abs"
    if [[ "$skills_rel" = /* ]]; then skills_rel="${skills_rel#"$ROOT"/}"; fi
    awk -F'\t' -v a="$skills_abs" -v r="$skills_rel" '
        function skill_of(p,  n) {
            if (index(p, a "/") == 1) p = substr(p, length(a) + 2)
            else if (index(p, r "/") == 1) p = substr(p, length(r) + 2)
            n = index(p, "/")
            return (n > 0) ? substr(p, 1, n - 1) : "(root)"
        }
        NF >= 3 {
            s = skill_of($2)
            if (!seen[s, $1]++) c[s]++
        }
        END { for (s in c) print s "\t" c[s] }' "$tmp/cites" \
        | LC_ALL=C sort > "$tmp/coverage"

    # --probe: one request per unknown URL, ten seconds apart, never a URL the
    # manifest already knows. A known URL is sound by construction.
    : > "$tmp/moved"
    : > "$tmp/down"
    if [[ "$PROBE" -eq 1 ]]; then
        local delay=10 first=1 code loc target
        if [[ -n "$PROBE_FILE" || "$ALLOW_FAST" -eq 1 ]]; then
            delay=0
        fi
        awk -F'\t' 'NF { if (!u[$1]++) print $1 }' "$tmp/unknown" > "$tmp/probe_urls"
        while IFS= read -r u; do
            [[ -n "$u" ]] || continue
            if [[ "$first" -eq 0 && "$delay" -gt 0 ]]; then sleep "$delay"; fi
            first=0
            IFS=$'\t' read -r code loc <<<"$(probe_target "$u")"
            case "$code" in
                2??) : ;;
                301|302|303|307|308)
                    target="${loc%/}"
                    if [[ -n "$target" && "$target" != "$u" ]]; then
                        printf '%s\t%s\t%s\n' "$u" "$code" "$target" >> "$tmp/moved"
                    fi ;;
                0) log "warn: probe failed for $u" ;;
                *) printf '%s\t%s\n' "$u" "$code" >> "$tmp/down" ;;
            esac
        done < "$tmp/probe_urls"
    fi
    n_moved="$(awk -F'\t' 'NF { c++ } END { print c + 0 }' "$tmp/moved")"
    n_down="$(awk -F'\t' 'NF { c++ } END { print c + 0 }' "$tmp/down")"

    if [[ "$JSON_OUT" -eq 1 ]]; then
        jq -n \
            --arg manifest "$manifest_path" --argjson articles "$articles" \
            --arg prev "$prev" --arg curr "$curr" --argjson snaps "$have_snapshots" \
            --argjson cited "$cited" --argjson references "$references" \
            --argjson files "$files" --argjson n_unknown "$n_unknown" \
            --argjson n_uncited "$n_uncited" --argjson n_stale "$n_stale" \
            --argjson n_moved "$n_moved" --argjson n_down "$n_down" \
            --arg unknown_tsv "$(cat "$tmp/unknown")" \
            --arg uncited_tsv "$(cat "$tmp/uncited")" \
            --arg stale_tsv "$(cat "$tmp/stale")" \
            --arg coverage_tsv "$(cat "$tmp/coverage")" \
            --arg moved_tsv "$(cat "$tmp/moved")" \
            --arg down_tsv "$(cat "$tmp/down")" '
            def rows(s): s | split("\n") | map(select(length > 0)) | map(split("\t"));
            (rows($unknown_tsv)
             | group_by(.[0])
             | map({key: .[0][0],
                    value: map({file: .[1], line: (.[2] | tonumber)})})
             | from_entries) as $refs
            | {
                manifest: {path: $manifest, articles: $articles},
                snapshots: (if $snaps == 1 then {prev: $prev, curr: $curr} else null end),
                counts: {
                    articles: $articles, cited: $cited, references: $references,
                    files: $files, unknown: $n_unknown, uncited_new: $n_uncited,
                    stale: $n_stale, moved: $n_moved, down: $n_down
                },
                unknown: (rows($unknown_tsv) | group_by(.[0]) | map({
                    url: .[0][0],
                    references: map({file: .[1], line: (.[2] | tonumber)})
                })),
                uncited_new: (rows($uncited_tsv)
                    | map({url: .[0], title: .[1], modified: .[2]})),
                stale: (rows($stale_tsv) | map({
                    url: .[0], modified: .[1], file: .[2],
                    line: (.[3] | tonumber), committed: .[4]
                })),
                coverage: (rows($coverage_tsv) | map({
                    skill: .[0], cited: (.[1] | tonumber), articles: $articles
                })),
                moved: (rows($moved_tsv) | map({
                    url: .[0], status: (.[1] | tonumber), location: .[2],
                    references: ($refs[.[0]] // [])
                })),
                down: (rows($down_tsv) | map({
                    url: .[0], status: (.[1] | tonumber),
                    references: ($refs[.[0]] // [])
                }))
              }'
    else
        printf 'KB citation audit\n'
        printf '  %-12s %s articles  %s\n' "manifest" "$articles" "$manifest_path"
        printf '  %-12s %s distinct, %s references in %s files\n' \
            "cited" "$cited" "$references" "$files"
        if [[ "$have_snapshots" -eq 1 ]]; then
            printf '  %-12s %s..%s\n' "snapshots" "$prev" "$curr"
        else
            printf '  %-12s fewer than two; uncited-new not checked\n' "snapshots"
        fi
        printf '  %-12s %s\n' "unknown" "$n_unknown"
        printf '  %-12s %s\n' "uncited-new" "$n_uncited"
        printf '  %-12s %s\n' "stale" "$n_stale"
        if [[ "$PROBE" -eq 1 ]]; then
            printf '  %-12s %s\n' "moved" "$n_moved"
            printf '  %-12s %s\n' "down" "$n_down"
        else
            printf '  %-12s not checked (--probe)\n' "moved/down"
        fi

        if [[ -s "$tmp/coverage" ]]; then
            printf '\ncoverage (distinct articles cited, of %s)\n' "$articles"
            while IFS=$'\t' read -r f d; do
                printf '  %-30s %4s\n' "$f" "$d"
            done < "$tmp/coverage"
        fi

        if [[ -s "$tmp/unknown" ]]; then
            printf '\nunknown (cited but not in the manifest)\n'
            awk -F'\t' 'NF { if ($1 != prev) { printf "  %s\n", $1; prev = $1 }
                printf "    %s:%s\n", $2, $3 }' "$tmp/unknown"
        fi
        if [[ -s "$tmp/moved" ]]; then
            printf '\nmoved (redirected; update the citation)\n'
            awk -F'\t' 'NF { printf "  %s\n    -> %s  HTTP %s\n", $1, $3, $2 }' \
                "$tmp/moved"
        fi
        if [[ -s "$tmp/down" ]]; then
            printf '\ndown (the URL no longer resolves)\n'
            awk -F'\t' 'NF { printf "  %s  HTTP %s\n", $1, $2 }' "$tmp/down"
        fi
        if [[ -s "$tmp/uncited" ]]; then
            printf '\nuncited-new (added since %s, no skill cites it)\n' "$prev"
            awk -F'\t' 'NF { printf "  %s  %s\n", $1, $2 }' "$tmp/uncited"
        fi
        if [[ -s "$tmp/stale" ]]; then
            printf '\nstale (article modified after the citing file was last committed)\n'
            awk -F'\t' 'NF { printf "  %s\n    modified %s > %s  %s:%s\n", $1, $2, $5, $3, $4 }' \
                "$tmp/stale"
        fi
    fi

    findings=$((n_unknown + n_moved + n_down))
    log "$n_unknown unknown, $n_moved moved, $n_down down; $n_uncited uncited-new, $n_stale stale (advisory)"
    if [[ "$findings" -gt 0 ]]; then
        exit 3
    fi
}

# --- extract ----------------------------------------------------------------

cmd_extract() {
    local -a args=()

    if [[ "$ALL" -eq 1 ]]; then
        args+=(--all)
    else
        [[ -n "$SLUG" ]] || die "extract needs --slug SLUG or --all"
        args+=(--slug "$SLUG")
    fi
    [[ -n "$FORMAT" ]] && args+=(--format "$FORMAT")
    "$SCRAPER" "${args[@]}" "${PASSTHRU[@]}"
}

# --- prune ------------------------------------------------------------------

# Snapshots are regenerable, but they are also the change history, so this is a
# dry run unless --yes is given, it never removes the newest snapshot, and it
# never removes the one `latest` points at.
cmd_prune() {
    local keep="${KEEP:-5}" target="" name i count=0 kept=0 freed=0
    local -a all=() remove=()
    local -a keep_names=()

    [[ "$keep" =~ ^[0-9]+$ ]] || die "--keep must be a number"
    [[ "$keep" -ge 1 ]] || die "--keep must be at least 1"

    while IFS= read -r name; do
        [[ -n "$name" ]] && all+=("$name")
    done < <(snapshot_names | sort -r)

    target="$(latest_snapshot || true)"
    target="${target##*/}"

    for ((i = 0; i < ${#all[@]}; i++)); do
        name="${all[$i]}"
        if [[ "$i" -lt "$keep" || "$name" == "$target" ]]; then
            keep_names+=("$name")
            kept=$((kept + 1))
        else
            remove+=("$name")
        fi
    done

    if [[ ${#all[@]} -eq 0 ]]; then
        printf 'nothing to prune: no completed snapshots in %s\n' "${CACHE#"$ROOT"/}"
        return 0
    fi

    if [[ ${#remove[@]} -eq 0 ]]; then
        printf 'nothing to prune: %s snapshots, keeping %s\n' "${#all[@]}" "$keep"
        return 0
    fi

    for name in "${remove[@]}"; do
        count=$((count + $(du -sb "$CACHE/$name" 2>/dev/null | cut -f1)))
    done

    if [[ "$JSON_OUT" -eq 1 ]]; then
        jq -n --argjson keep "$keep" --argjson removed "$YES" \
            --argjson freed "$count" \
            --arg keep_names "$(printf '%s\n' "${keep_names[@]}")" \
            --arg remove_names "$(printf '%s\n' "${remove[@]}")" '
            def lines: split("\n") | map(select(length > 0));
            {keep: $keep, removed: ($removed == 1),
             snapshots_kept: ($keep_names | lines),
             snapshots_removed: ($remove_names | lines),
             freed_bytes: (if $removed == 1 then $freed else 0 end)}'
    else
        printf 'keeping: %s\n' "$(printf '%s ' "${keep_names[@]}")"
        printf 'removing: %s\n' "$(printf '%s ' "${remove[@]}")"
    fi

    if [[ "$YES" -eq 1 ]]; then
        for name in "${remove[@]}"; do
            rm -rf "${CACHE:?}/$name"
        done
        freed="$count"
        log "pruned ${#remove[@]} snapshot(s), freed $(human_size "$freed")"
    else
        log "dry run: ${#remove[@]} snapshot(s), $(human_size "$count") would be freed; rerun with --yes"
    fi
}

# --- dispatch ---------------------------------------------------------------

case "$COMMAND" in
    status)  cmd_status ;;
    check)   cmd_check ;;
    refresh) cmd_refresh ;;
    list)    cmd_list ;;
    search)  cmd_search ;;
    diff)    cmd_diff ;;
    affected) cmd_affected ;;
    audit)   cmd_audit ;;
    extract) cmd_extract ;;
    prune)   cmd_prune ;;
    help)    usage; exit 0 ;;
    "")      usage >&2; exit 2 ;;
    *)       log "error: unknown command: $COMMAND"; usage >&2; exit 2 ;;
esac
