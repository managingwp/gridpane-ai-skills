#!/usr/bin/env bash
#
# test_kb_docs.sh - offline test for scripts/gridpane-kb-docs.sh affected.
#
# Builds two fixture snapshots and a fixture skills tree, then asserts the join
# between the snapshot diff and the KB URLs the skills cite: cited changes,
# uncited changes hidden until --all, removed and title-only rows, the JSON
# shape, the stderr counts, the error paths, and that a read-only command writes
# nothing. No network, no writes outside the temporary directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLI="$REPO_ROOT/scripts/gridpane-kb-docs.sh"

usage() {
    cat <<EOF
Usage: bash tests/scripts/test_kb_docs.sh

Offline test for 'gridpane-kb-docs.sh affected'. Exits 0 when every case passes,
1 on the first failure, 2 on a bad argument. Touches no network.
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "") : ;;
    *) printf 'error: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
esac

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ok() { printf 'ok: %s\n' "$1"; }

[[ -x "$CLI" ]] || fail "not executable: $CLI"
command -v jq >/dev/null 2>&1 || fail "jq is required"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CACHE="$WORK/cache"
SKILLS="$WORK/skills"
mkdir -p "$CACHE/2026-01-01" "$CACHE/2026-01-02" "$SKILLS/x"

entry() {
    printf '{"url":"https://gridpane.com/kb/%s/","sha256":"%s","title":"%s"}' \
        "$1" "$2" "$3"
}

# old snapshot: a b c d e. new snapshot: a and c changed, d removed,
# e title-only (same body hash), b untouched.
{
    printf '{"schema":2,"source":"fixture","count":5,"entries":['
    printf '%s,' "$(entry a 111 A)" "$(entry b 222 B)" "$(entry c 333 C)" \
        "$(entry d 444 D)"
    printf '%s]}\n' "$(entry e 555 'E old')"
} > "$CACHE/2026-01-01/manifest.json"
{
    printf '{"schema":2,"source":"fixture","count":4,"entries":['
    printf '%s,' "$(entry a 999 A)" "$(entry b 222 B)" "$(entry c 777 C)"
    printf '%s]}\n' "$(entry e 555 'E new')"
} > "$CACHE/2026-01-02/manifest.json"

# One markdown file citing a twice (two rows), plus b (unchanged), d (removed)
# and e (title-only). Files and URLs that must be ignored are alongside it.
cat > "$SKILLS/x/SKILL.md" <<'MD'
https://gridpane.com/kb/a/
https://gridpane.com/kb/b/
https://gridpane.com/kb/d/
https://gridpane.com/kb/e/
https://gridpane.com/kb/a/
MD
printf 'https://gridpane.com/kb/c/\n' > "$SKILLS/x/notes.txt"
printf 'https://gridpane.com/blog/not-kb/\n' > "$SKILLS/x/post.md"

SKILL_MD="$SKILLS/x/SKILL.md"

# A cached API page, so `extract --snapshot` has a body to read. The wrapper
# resolves a snapshot name against the cache, not against the working directory.
printf '[{"slug":"a","content":{"rendered":"<p>Hello <b>world</b></p>"}}]\n' \
    > "$CACHE/2026-01-01/api-page-1.json"

# --- changed and cited ------------------------------------------------------

before_fixtures="$(find "$CACHE" "$SKILLS" -type f -exec sha256sum {} + \
    | LC_ALL=C sort)"
before_repo="$(git -C "$REPO_ROOT" status --porcelain)"

out="$("$CLI" affected --cache "$CACHE" --skills "$SKILLS" 2>"$WORK/stderr")"

cat > "$WORK/expected" <<EOF
changed	https://gridpane.com/kb/a	$SKILL_MD:1
changed	https://gridpane.com/kb/a	$SKILL_MD:5
removed	https://gridpane.com/kb/d	$SKILL_MD:3
title	https://gridpane.com/kb/e	$SKILL_MD:4
EOF

diff -u "$WORK/expected" <(printf '%s\n' "$out") >&2 \
    || fail "affected rows are not the expected status/url/file:line set"
ok "cited changes produce one row per file:line"
ok "uncited changes are hidden by default"

grep -q 'https://gridpane.com/kb/b' <<<"$out" && fail "unchanged article b was reported"
ok "an unchanged article is not reported"

grep -q 'notes.txt' <<<"$out" && fail "a non-markdown file was scanned"
grep -q 'not-kb' <<<"$out" && fail "a non-/kb/ URL was reported"
ok "only markdown KB citations are scanned"

grep -q '^4 changed, 3 cited, 4 references in 1 files (2026-01-01..2026-01-02)$' \
    "$WORK/stderr" \
    || fail "stderr summary is wrong: $(cat "$WORK/stderr")"
ok "stderr summary counts changed, cited, references and files"

# --- nothing written --------------------------------------------------------

after_fixtures="$(find "$CACHE" "$SKILLS" -type f -exec sha256sum {} + \
    | LC_ALL=C sort)"
[[ "$before_fixtures" == "$after_fixtures" ]] \
    || fail "affected modified the fixture snapshots or skills"
after_repo="$(git -C "$REPO_ROOT" status --porcelain)"
[[ "$before_repo" == "$after_repo" ]] \
    || fail "affected modified the checkout"
ok "affected writes nothing"

# --- --all ------------------------------------------------------------------

out_all="$("$CLI" affected --cache "$CACHE" --skills "$SKILLS" --all 2>/dev/null)"
grep -q '^changed	https://gridpane.com/kb/c	-$' <<<"$out_all" \
    || fail "--all did not list the uncited change with a - location"
[[ "$(wc -l <<<"$out_all")" -eq 5 ]] || fail "--all row count is not 5"
ok "--all lists an uncited change with a - location"

# --- --json -----------------------------------------------------------------

json="$("$CLI" affected --cache "$CACHE" --skills "$SKILLS" --json 2>/dev/null)"
jq -e . >/dev/null <<<"$json" || fail "--json is not valid JSON"
jq -e '.prev == "2026-01-01" and .curr == "2026-01-02"' <<<"$json" >/dev/null \
    || fail "--json snapshot pair is wrong"
jq -e '.counts == {changed: 4, cited: 3, references: 4, files: 1}' <<<"$json" \
    >/dev/null || fail "--json counts are wrong: $(jq -c .counts <<<"$json")"
jq -e '.rows | length == 4' <<<"$json" >/dev/null || fail "--json row count is wrong"
jq -e --arg f "$SKILL_MD" '.rows[0].file == $f and .rows[0].line == 1' <<<"$json" \
    >/dev/null || fail "--json row file/line is wrong"
ok "--json carries prev, curr, counts and rows"

# --- explicit PREV and error paths ------------------------------------------

out_prev="$("$CLI" affected 2026-01-01 --cache "$CACHE" --skills "$SKILLS" 2>/dev/null)"
[[ "$out_prev" == "$out" ]] || fail "an explicit PREV changed the result"
ok "an explicit PREV snapshot is honoured"

if "$CLI" affected 1999-01-01 --cache "$CACHE" --skills "$SKILLS" \
        >/dev/null 2>"$WORK/err-unknown"; then
    fail "an unknown snapshot exited 0"
fi
grep -q 'unknown snapshot' "$WORK/err-unknown" \
    || fail "unknown snapshot did not explain itself"
ok "an unknown snapshot exits non-zero"

mkdir -p "$WORK/one/2026-01-01"
cp "$CACHE/2026-01-01/manifest.json" "$WORK/one/2026-01-01/manifest.json"
if "$CLI" affected --cache "$WORK/one" --skills "$SKILLS" \
        >/dev/null 2>"$WORK/err-one"; then
    fail "a single snapshot exited 0"
fi
grep -q 'one snapshot only' "$WORK/err-one" \
    || fail "a single snapshot did not explain itself"
ok "a single snapshot exits non-zero with a PREV hint"

# --- --prev-manifest: a stored baseline instead of an earlier snapshot -------

BASELINE="$WORK/baseline.json"
cp "$CACHE/2026-01-01/manifest.json" "$BASELINE"

out_baseline="$("$CLI" affected --prev-manifest "$BASELINE" \
    --cache "$CACHE" --skills "$SKILLS" 2>/dev/null)"
[[ "$out_baseline" == "$out" ]] \
    || fail "a baseline manifest produced different rows than the snapshot it copies"
ok "a baseline manifest reproduces the snapshot comparison byte for byte"

json_baseline="$("$CLI" affected --prev-manifest "$BASELINE" \
    --cache "$CACHE" --skills "$SKILLS" --json 2>/dev/null)"
jq -e '.prev == "baseline.json" and .curr == "2026-01-02"' <<<"$json_baseline" >/dev/null \
    || fail "--prev-manifest JSON names the wrong pair: $(jq -c '{prev,curr}' <<<"$json_baseline")"
jq -e '.counts == {changed: 4, cited: 3, references: 4, files: 1}' <<<"$json_baseline" \
    >/dev/null || fail "--prev-manifest JSON counts are wrong"
ok "--prev-manifest labels the baseline in JSON and keeps the counts"

if "$CLI" affected --prev-manifest "$WORK/missing.json" \
        --cache "$CACHE" --skills "$SKILLS" >/dev/null 2>"$WORK/err-missing"; then
    fail "a missing baseline manifest exited 0"
fi
grep -q 'baseline manifest not found' "$WORK/err-missing" \
    || fail "a missing baseline manifest did not explain itself"
ok "a missing baseline manifest exits non-zero"

printf '{"schema":2}\n' > "$WORK/not-a-manifest.json"
if "$CLI" affected --prev-manifest "$WORK/not-a-manifest.json" \
        --cache "$CACHE" --skills "$SKILLS" >/dev/null 2>"$WORK/err-shape"; then
    fail "a malformed baseline manifest exited 0"
fi
grep -q 'not a manifest' "$WORK/err-shape" \
    || fail "a malformed baseline manifest did not explain itself"
ok "a malformed baseline manifest exits non-zero"

if "$CLI" affected 2026-01-01 --prev-manifest "$BASELINE" \
        --cache "$CACHE" --skills "$SKILLS" >/dev/null 2>"$WORK/err-both"; then
    fail "a snapshot argument combined with --prev-manifest exited 0"
fi
grep -q 'cannot be combined' "$WORK/err-both" \
    || fail "the combination error did not explain itself"
ok "a positional PREV and --prev-manifest are mutually exclusive"

# --- extract from a named snapshot ------------------------------------------

out_extract="$("$CLI" extract --slug a --snapshot 2026-01-01 --cache "$CACHE" 2>&1)"
grep -q 'wrote .*2026-01-01/a.md' <<<"$out_extract" \
    || fail "extract --snapshot did not write the extracted body: $out_extract"
grep -q 'Hello' "$CACHE/2026-01-01/a.md" \
    || fail "extract --snapshot wrote no article text"
ok "extract reads a named snapshot without --offline"

# --- audit ------------------------------------------------------------------

audit_entry() {
    printf '{"url":"https://gridpane.com/kb/%s/","sha256":"%s","title":"%s","modified":"%s"}' \
        "$1" "$2" "$3" "$4"
}

AUDIT="$WORK/audit"
mkdir -p "$AUDIT/cache/2026-01-01" "$AUDIT/cache/2026-01-02" \
    "$AUDIT/skills/alpha" "$AUDIT/skills/beta"

{
    printf '{"schema":2,"source":"fixture","count":2,"entries":['
    printf '%s,' "$(audit_entry a 111 A 2026-01-01T00:00:00)"
    printf '%s]}\n' "$(audit_entry b 222 B 2026-01-01T00:00:00)"
} > "$AUDIT/cache/2026-01-01/manifest.json"
cp "$AUDIT/cache/2026-01-01/manifest.json" "$AUDIT/cache/2026-01-02/manifest.json"
cp "$AUDIT/cache/2026-01-02/manifest.json" "$AUDIT/manifest.json"

# a and b are cited; not-an-article sits in a fenced example and must not count.
cat > "$AUDIT/skills/alpha/SKILL.md" <<'MD'
https://gridpane.com/kb/a/
https://gridpane.com/kb/b/

```
https://gridpane.com/kb/not-an-article/
```
MD
printf 'https://gridpane.com/kb/b/\n' > "$AUDIT/skills/beta/SKILL.md"

audit_run() {
    local dir="$1"
    shift
    if AUDIT_OUT="$("$CLI" audit --manifest "$dir/manifest.json" \
            --cache "$dir/cache" --skills "$dir/skills" "$@" 2>"$WORK/audit-stderr")"; then
        AUDIT_STATUS=0
    else
        AUDIT_STATUS=$?
    fi
}

audit_run "$AUDIT"
[[ "$AUDIT_STATUS" -eq 0 ]] || fail "a clean audit exited $AUDIT_STATUS"
grep -q '^  unknown *0$' <<<"$AUDIT_OUT" || fail "a clean audit is not clean"
grep -q 'not-an-article' <<<"$AUDIT_OUT" \
    && fail "a fenced example was treated as a citation"
ok "a clean fixture exits 0 and skips fenced examples"

audit_run "$AUDIT" --json
jq -e '.counts.unknown == 0 and .counts.uncited_new == 0 and .counts.stale == 0' \
    <<<"$AUDIT_OUT" >/dev/null || fail "clean audit counts are wrong"
jq -e '.counts.cited == 2 and .counts.references == 3' <<<"$AUDIT_OUT" >/dev/null \
    || fail "clean audit citation counts are wrong: $(jq -c .counts <<<"$AUDIT_OUT")"
jq -e '.coverage | map(.skill) | sort == ["alpha", "beta"]' <<<"$AUDIT_OUT" \
    >/dev/null || fail "coverage is not grouped per skill"
ok "audit --json reports counts, coverage and the empty finding sets"

FIND="$WORK/audit-findings"
mkdir -p "$FIND/cache/2026-01-01" "$FIND/cache/2026-01-02" "$FIND/skills/alpha"
{
    printf '{"schema":2,"source":"fixture","count":2,"entries":['
    printf '%s,' "$(audit_entry a 111 A 2026-01-01T00:00:00)"
    printf '%s]}\n' "$(audit_entry b 222 B 2026-01-01T00:00:00)"
} > "$FIND/cache/2026-01-01/manifest.json"
{
    printf '{"schema":2,"source":"fixture","count":3,"entries":['
    printf '%s,' "$(audit_entry a 111 A 2026-01-01T00:00:00)"
    printf '%s,' "$(audit_entry b 222 B 2026-01-01T00:00:00)"
    printf '%s]}\n' "$(audit_entry d 444 D 2026-01-15T00:00:00)"
} > "$FIND/cache/2026-01-02/manifest.json"
{
    printf '{"schema":2,"source":"fixture","count":2,"entries":['
    printf '%s,' "$(audit_entry a 111 A 2026-02-01T00:00:00)"
    printf '%s]}\n' "$(audit_entry b 222 B 2026-01-01T00:00:00)"
} > "$FIND/manifest.json"

cat > "$FIND/skills/alpha/SKILL.md" <<'MD'
https://gridpane.com/kb/a/
https://gridpane.com/kb/zzz/
https://gridpane.com/kb/gone/
MD
git -C "$FIND/skills" init -q
git -C "$FIND/skills" add alpha/SKILL.md
GIT_AUTHOR_DATE=2026-01-01T00:00:00 GIT_COMMITTER_DATE=2026-01-01T00:00:00 \
    git -C "$FIND/skills" -c user.name=test -c user.email=test@example.com \
    commit -q -m fixture

audit_run "$FIND"
[[ "$AUDIT_STATUS" -eq 3 ]] || fail "an unsound citation exited $AUDIT_STATUS, not 3"
grep -q 'https://gridpane.com/kb/zzz$' <<<"$AUDIT_OUT" \
    || fail "a cited-but-unknown slug was not reported"
grep -q '^  uncited-new *1$' <<<"$AUDIT_OUT" \
    || fail "an added-and-uncited article was not reported"
grep -q '^  stale *1$' <<<"$AUDIT_OUT" \
    || fail "a file committed before the article's modified date is not stale"
grep -q 'modified 2026-02-01 > 2026-01-01' <<<"$AUDIT_OUT" \
    || fail "the stale row does not explain the comparison"
ok "unknown exits 3, and uncited-new and stale are reported"

audit_run "$FIND" --json
jq -e '.counts.unknown == 2 and .counts.uncited_new == 1 and .counts.stale == 1' \
    <<<"$AUDIT_OUT" >/dev/null \
    || fail "findings counts are wrong: $(jq -c .counts <<<"$AUDIT_OUT")"
jq -e '.uncited_new[0].url == "https://gridpane.com/kb/d"' <<<"$AUDIT_OUT" \
    >/dev/null || fail "the uncited article is not d"
jq -e '.stale[0] | .url == "https://gridpane.com/kb/a" and .committed == "2026-01-01"' \
    <<<"$AUDIT_OUT" >/dev/null || fail "the stale entry is wrong"
jq -e '.unknown | map(.url) | sort
       == ["https://gridpane.com/kb/gone", "https://gridpane.com/kb/zzz"]' \
    <<<"$AUDIT_OUT" >/dev/null || fail "unknown is not the two uncited slugs"
ok "audit --json carries unknown, uncited_new and stale"

cat > "$WORK/probe.json" <<'JSON'
{"https://gridpane.com/kb/zzz": {"status": 301,
  "location": "https://gridpane.com/kb/zzz-new/"},
 "https://gridpane.com/kb/gone": {"status": 404}}
JSON
audit_run "$FIND" --probe --probe-file "$WORK/probe.json" --json
[[ "$AUDIT_STATUS" -eq 3 ]] || fail "--probe with a moved/down fixture exited $AUDIT_STATUS"
jq -e '.counts.moved == 1 and .counts.down == 1' <<<"$AUDIT_OUT" >/dev/null \
    || fail "probe counts are wrong: $(jq -c .counts <<<"$AUDIT_OUT")"
jq -e '.moved[0].location == "https://gridpane.com/kb/zzz-new"' <<<"$AUDIT_OUT" \
    >/dev/null || fail "the redirect target was not normalised"
jq -e '.down[0].status == 404' <<<"$AUDIT_OUT" >/dev/null \
    || fail "the 404 was not reported as down"
jq -e '.moved[0].references | length == 1' <<<"$AUDIT_OUT" >/dev/null \
    || fail "a probe finding lost its citation reference"
ok "--probe reports moved and down from a saved response, without network"

audit_run "$FIND" --probe --probe-file "$WORK/probe.json" \
    --ignore https://gridpane.com/kb/zzz/ --ignore https://gridpane.com/kb/gone/
[[ "$AUDIT_STATUS" -eq 0 ]] || fail "--ignore did not clear the findings ($AUDIT_STATUS)"
grep -q '^  unknown *0$' <<<"$AUDIT_OUT" || fail "--ignore left an unknown URL"
ok "--ignore suppresses a deliberate exception"

[[ -z "$(git -C "$FIND/skills" status --porcelain)" ]] \
    || fail "audit modified the fixture tree"
ok "audit writes nothing"

# --- help -------------------------------------------------------------------

"$CLI" --help | grep -q 'affected' || fail "--help does not list affected"
"$CLI" --help | grep -q 'audit' || fail "--help does not list audit"
ok "affected and audit appear in --help"

printf 'all cases passed\n'
