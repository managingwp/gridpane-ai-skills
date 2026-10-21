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
FORCE=0
JSON_OUT=0
PASSTHRU=()

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} <command> [options]

Scrape, inspect and manage the GridPane Knowledge Base cache.

Commands:
  status              What is ingested, cached and extracted (local only)
  check               One request: exit 0 unchanged, 3 changed
  refresh             Probe, index a new snapshot, diff, publish the manifest
  help                Show this help and exit

Options:
  --offline           refresh: skip the probe and rebuild from the newest snapshot
  --force             refresh: pass --force to the indexer (accept a count drop)
  --json              check/refresh: print a JSON object instead of plain lines
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
        --force)      FORCE=1; shift ;;
        --json)       JSON_OUT=1; shift ;;
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
        *) log "error: unknown option: $1"; usage >&2; exit 2 ;;
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
    local name=""
    if [[ -L "$CACHE/latest" ]]; then
        name="$(readlink "$CACHE/latest")"
    elif [[ -f "$CACHE/latest" ]]; then
        name="$(head -1 "$CACHE/latest")"
    fi
    [[ -n "$name" ]] || return 1
    [[ -f "$CACHE/$name/manifest.json" ]] || return 1
    printf '%s' "$CACHE/$name"
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

cmd_status() {
    local ingested="-" schema="?" fetched="-" snap="" cached="-" files="-"
    local size="-" extracted="-" drift="" snapshots="" snap_count=0

    if [[ -f "$MANIFEST" ]]; then
        ingested="$(jq -r '.count // "-"' "$MANIFEST" 2>/dev/null || printf '-')"
        schema="$(jq -r '.schema // "?"' "$MANIFEST" 2>/dev/null || printf '?')"
        fetched="$(jq -r '.fetched_at // "-"' "$MANIFEST" 2>/dev/null || printf '-')"
    fi

    snap="$(latest_snapshot || true)"
    if [[ -n "$snap" ]]; then
        cached="$(jq -r '.count // 0' "$snap/manifest.json")"
        files="$(find "$snap" -type f | wc -l | tr -d ' ')"
        size="$(du -sh "$snap" 2>/dev/null | cut -f1)"
        extracted="$(find "$snap" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
        if [[ -f "$MANIFEST" ]]; then
            drift="$(drift_counts "$MANIFEST" "$snap/manifest.json")"
        fi
    fi

    snapshots="$(snapshot_names | awk 'BEGIN { ORS="" } { print (NR > 1 ? ", " : "") $0 }')"
    snap_count="$(snapshot_names | wc -l | tr -d ' ')"

    printf 'KB status\n'
    printf '  %-10s %4s articles  %s\n' "ingested" "$ingested" \
        "${MANIFEST#"$ROOT"/} (schema $schema, fetched $fetched)"
    if [[ -n "$snap" ]]; then
        printf '  %-10s %4s articles  snapshot %s (%s files, %s)\n' \
            "cached" "$cached" "$(basename "$snap")" "$files" "$size"
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
        printf '  %-10s %s  %s\n' "newest" \
            "$(jq -r '[.entries[] | select(.modified != "")]
                      | max_by(.modified) | .modified // "-"' "$snap/manifest.json")" \
            "$(jq -r '[.entries[] | select(.modified != "")]
                      | max_by(.modified) | (.url // "-")
                      | sub(".*/kb/"; "") | sub("/$"; "")' "$snap/manifest.json")"
    fi
    printf '  %-10s %4s  %s\n' "snapshots" "$snap_count" "${snapshots:--}"

    if [[ ! -f "$MANIFEST" ]]; then
        log "hint: no committed manifest yet; run: ${SCRIPT_NAME} refresh"
    fi
    if [[ -z "$snap" ]]; then
        log "hint: no cached snapshot yet; run: ${SCRIPT_NAME} refresh"
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

# --- dispatch ---------------------------------------------------------------

case "$COMMAND" in
    status)  cmd_status ;;
    check)   cmd_check ;;
    refresh) cmd_refresh ;;
    help)    usage; exit 0 ;;
    "")      usage >&2; exit 2 ;;
    *)       log "error: unknown command: $COMMAND"; usage >&2; exit 2 ;;
esac
