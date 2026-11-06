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

# --- extract from a named snapshot ------------------------------------------

out_extract="$("$CLI" extract --slug a --snapshot 2026-01-01 --cache "$CACHE" 2>&1)"
grep -q 'wrote .*2026-01-01/a.md' <<<"$out_extract" \
    || fail "extract --snapshot did not write the extracted body: $out_extract"
grep -q 'Hello' "$CACHE/2026-01-01/a.md" \
    || fail "extract --snapshot wrote no article text"
ok "extract reads a named snapshot without --offline"

# --- help -------------------------------------------------------------------

"$CLI" --help | grep -q 'affected' || fail "--help does not list affected"
ok "affected appears in --help"

printf 'all cases passed\n'
