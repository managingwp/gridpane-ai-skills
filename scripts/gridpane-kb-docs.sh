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
# Exit status: 0 success, 3 check found changes, 2 usage error, 1 failure.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRAPER="$ROOT/skills/gridpane-tooling/scripts/scrape-docs.sh"
MANIFEST="$ROOT/skills/gridpane-tooling/references/docs-manifest.json"
CACHE="$ROOT/out/gridpane-docs-cache"

COMMAND=""
OFFLINE=0
REMOTE=0
FORCE=0
JSON_OUT=0
FILTER=""
LIMIT=""
SLUG=""
EXTRACT_ALL=0
FORMAT=""
KEEP=""
YES=0
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
  extract             Cached article body as text or markdown
  prune               Remove old snapshots (dry run unless --yes)
  help                Show this help and exit

Options:
  --offline           refresh: skip the probe and rebuild from the newest snapshot
  --force             refresh: pass --force to the indexer (accept a count drop)
  --json              Print JSON instead of plain lines (status, check, refresh,
                      list, search, diff, prune)
  --filter TEXT       list: keep rows whose slug or title contains TEXT
  --limit N           list/search: at most N rows (list default 20)
  --slug SLUG         extract: the article to convert
  --all               extract: convert every article in the snapshot
  --format text|markdown  extract: output format (default markdown)
  --keep N            prune: snapshots to keep, newest first (default 5)
  --yes               prune: actually delete; without it nothing is removed
  --manifest FILE     refresh: publish to this path instead of the committed one
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
        --all)        EXTRACT_ALL=1; shift ;;
        --format)     FORMAT="${2:?--format needs a value}"; shift 2 ;;
        --format=*)   FORMAT="${1#--format=}"; shift ;;
        --keep)       KEEP="${2:?--keep needs a value}"; shift 2 ;;
        --keep=*)     KEEP="${1#--keep=}"; shift ;;
        --yes)        YES=1; shift ;;
        --manifest)   MANIFEST="${2:?--manifest needs a value}"; shift 2 ;;
        --manifest=*) MANIFEST="${1#--manifest=}"; shift ;;
        -h|--help)    usage; exit 0 ;;
        --base|--cache|--snapshot|--partial|--probe-json)
            PASSTHRU+=("$1"); shift
            [[ $# -gt 0 ]] || die "$1 needs a value"
            PASSTHRU+=("$1"); shift ;;
        --base=*|--cache=*|--snapshot=*|--probe-json=*)
            PASSTHRU+=("$1"); shift ;;
        --allow-fast) PASSTHRU+=("$1"); shift ;;
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

# --- extract ----------------------------------------------------------------

cmd_extract() {
    local -a args=()

    if [[ "$EXTRACT_ALL" -eq 1 ]]; then
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
    extract) cmd_extract ;;
    prune)   cmd_prune ;;
    help)    usage; exit 0 ;;
    "")      usage >&2; exit 2 ;;
    *)       log "error: unknown command: $COMMAND"; usage >&2; exit 2 ;;
esac
