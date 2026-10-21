#!/usr/bin/env bash
#
# refresh-kb-docs.sh - refresh the committed GridPane KB manifest, safely.
#
# Wraps skills/gridpane-tooling/scripts/scrape-docs.sh so a refresh is one
# command with the politeness and guards always applied:
#
#   1. probe       one request: has any article changed since the last full run?
#                  (exit 0 and stop when nothing has)
#   2. index       full REST feed into a new dated snapshot, 10 s between
#                  requests, count/total/shape guards enforced by the scraper
#   3. diff        compare the new snapshot with the previous one
#   4. publish     copy the new manifest to
#                  skills/gridpane-tooling/references/docs-manifest.json, but only
#                  when its content actually changed
#
# Raw pages, extracted text and snapshots stay in the gitignored cache; the
# manifest is the only artifact that reaches git.
#
# Exit status: 0 success or nothing to do, 3 --check-only found changes,
# 2 usage error, 1 failure.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRAPER="$ROOT/skills/gridpane-tooling/scripts/scrape-docs.sh"
MANIFEST="$ROOT/skills/gridpane-tooling/references/docs-manifest.json"
CACHE="$ROOT/out/gridpane-docs-cache"

CHECK_ONLY=0
OFFLINE=0
FORCE=0
JSON_OUT=0
PASSTHRU=()

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Refresh the committed GridPane KB manifest: probe for changes, index the REST
feed into a new dated snapshot (10 s between requests), diff it against the
previous snapshot, and publish the manifest when its content changed.

Options:
  --check-only      Probe only. Exit 0 when nothing changed, 3 when something did
  --offline         Skip the probe and rebuild the manifest from the newest snapshot
  --force           Pass --force to the indexer (accept a >10% count drop)
  --json            Print a JSON summary instead of plain lines
  --manifest FILE   Publish to this path instead of the committed manifest
  -h, --help        Show this help and exit

Everything else is passed to scrape-docs.sh: --base, --cache, --snapshot,
--partial, --allow-fast (fixtures only). The 10 s delay is the scraper's
default and cannot be lowered for a live run without --allow-fast.
EOF
}

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check-only) CHECK_ONLY=1; shift ;;
        --offline)    OFFLINE=1; shift ;;
        --force)      FORCE=1; shift ;;
        --json)       JSON_OUT=1; shift ;;
        --manifest)   MANIFEST="${2:?--manifest needs a value}"; shift 2 ;;
        --manifest=*) MANIFEST="${1#--manifest=}"; shift ;;
        -h|--help)    usage; exit 0 ;;
        --base|--cache|--snapshot|--partial)
            PASSTHRU+=("$1"); shift
            [[ $# -gt 0 ]] || die "$1 needs a value"
            PASSTHRU+=("$1"); shift ;;
        --base=*|--cache=*|--snapshot=*)
            PASSTHRU+=("$1"); shift ;;
        --allow-fast) PASSTHRU+=("$1"); shift ;;
        *) log "error: unknown option: $1"; usage >&2; exit 2 ;;
    esac
done

[[ -x "$SCRAPER" ]] || die "scraper not found or not executable: $SCRAPER"
have() { command -v "$1" >/dev/null 2>&1; }
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

# Content of a manifest without timestamps, to decide whether the committed
# file needs rewriting at all.
manifest_fingerprint() {
    jq -S 'del(.fetched_at) | .entries |= map(del(.fetched_at))' "$1"
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

if [[ "$CHECK_ONLY" -eq 1 ]]; then
    [[ "$OFFLINE" -eq 0 ]] || die "--check-only and --offline are mutually exclusive"
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
fi

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

ARGS=()
[[ "$FORCE" -eq 1 ]] && ARGS+=(--force)
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
if [[ -f "$MANIFEST" ]]; then
    if ! diff -q <(manifest_fingerprint "$MANIFEST") \
            <(manifest_fingerprint "$snapshot/manifest.json") >/dev/null; then
        changed=1
    fi
else
    changed=1
fi

if [[ "$changed" -eq 1 ]]; then
    cp "$snapshot/manifest.json" "$MANIFEST.tmp"
    mv "$MANIFEST.tmp" "$MANIFEST"
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
