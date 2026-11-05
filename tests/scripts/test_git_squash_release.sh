#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2329
# The vendored suite uses `A && ok || bad` as its assertion idiom, keeps an
# unexpanded printf template (SC2016), and calls helpers from a trap (SC2329).
# =============================================================================
# tests/scripts/test_git_squash_release.sh -- dependency-free test suite for
# scripts/git-squash-release.sh
# -----------------------------------------------------------------------------
# Vendored 2026-11-05 from the canonical plan-generation-skill copy, with local
# cases for the Claude manifests and the CHANGELOG finalizer.
# Runs the bash port as a subprocess against throwaway git repos (with bare
# remotes) under a sandboxed TMPDIR so nothing in the real environment is
# touched. Exits 0 when all assertions pass, 1 otherwise.
# =============================================================================
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$HERE/../.." && pwd)
SCRIPT="$REPO_ROOT/scripts/git-squash-release.sh"
TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/gsr-tests.XXXXXX")

PASS=0
FAIL=0
ok () { PASS=$((PASS + 1)); }
bad () { FAIL=$((FAIL + 1)); printf 'not ok - %s\n' "$1"; }
assert_contains () { case "$1" in *"$2"*) ok ;; *) bad "$3 (expected to contain: '$2')" ;; esac; }
assert_not_contains () { case "$1" in *"$2"*) bad "$3 (unexpected: '$2')" ;; *) ok ;; esac; }
assert_eq () { [[ "$1" == "$2" ]] && ok || bad "$3 (expected '$2', got '$1')"; }
assert_status () { [[ "$1" == "$2" ]] && ok || bad "$3 (expected exit $2, got $1)"; }

cleanup () {
    cd /
    rm -rf "$TMPROOT"
}
trap cleanup EXIT

OUT=""
STATUS=0
# -- run <dir> [args...] : run the script with CWD=<dir>, capturing output + exit status
run () { local d="$1"; shift; OUT="$(cd "$d" && bash "$SCRIPT" "$@" 2>&1)"; STATUS=$?; }

# -- new_repo <name> -> prints the work-repo path (bare remote at <name>-remote.git)
new_repo () {
    local name="$1" r="$TMPROOT/$1"
    git init -q --bare "$TMPROOT/$name-remote.git"
    mkdir -p "$r"
    git -C "$r" init -q -b main
    git -C "$r" config user.email test@example.com
    git -C "$r" config user.name tester
    git -C "$r" remote add origin "$TMPROOT/$name-remote.git"
    printf '%s\n' "$r"
}

# -- seed_release_repo <name> [version] -> repo tagged v<version> + one commit since
seed_release_repo () {
    local name="$1" ver="${2:-1.0.0}" r
    r="$(new_repo "$name")"
    printf '%s\n' "$ver" > "$r/VERSION"
    git -C "$r" add -A
    git -C "$r" commit -qm "chore: init"
    git -C "$r" tag "v$ver"
    git -C "$r" push -qu origin main >/dev/null 2>&1
    git -C "$r" push -q origin "v$ver"
    printf 'x\n' > "$r/file.txt"
    git -C "$r" add -A
    git -C "$r" commit -qm "feat: change"
    printf '%s\n' "$r"
}

# =============================================================================
# -- Tests
# =============================================================================

# 1. --help
run / --help
assert_status "$STATUS" 0 "--help exits 0"
assert_contains "$OUT" "--detect" "--help lists --detect"
assert_contains "$OUT" "--squash" "--help lists --squash"
assert_contains "$OUT" "--bump" "--help lists --bump"
assert_contains "$OUT" "--skip-divergence-check" "--help lists --skip-divergence-check"

# 2. --detect on a bare repo (no tag/upstream/version source) fails, changes nothing
R="$(new_repo detectfail)"
echo a > "$R/a.txt"
git -C "$R" add -A
git -C "$R" commit -qm "init"
BEFORE="$(git -C "$R" rev-parse HEAD)"
run "$R" --detect
assert_status "$STATUS" 1 "--detect on incomplete repo exits 1"
assert_contains "$OUT" "[FAIL] Found latest tag" "--detect reports missing tag"
assert_eq "$(git -C "$R" rev-parse HEAD)" "$BEFORE" "--detect leaves HEAD unchanged"
assert_eq "$(git -C "$R" tag | wc -l | tr -d ' ')" "0" "--detect creates no tags"

# 3. --detect on a ready repo passes
R="$(seed_release_repo detectok)"
run "$R" --detect
assert_status "$STATUS" 0 "--detect on ready repo exits 0"
assert_contains "$OUT" "Current version detected from VERSION: 1.0.0" "--detect reports VERSION source"

# 4. standard minor release
R="$(seed_release_repo minor)"
run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 0 "minor release exits 0"
assert_eq "$(git -C "$R" rev-list --count v1.0.0..HEAD | tr -d ' ')" "1" "minor release leaves one commit since tag"
assert_eq "$(git -C "$R" log -1 --pretty=%s)" "Release v1.0.1" "minor release commit subject"
assert_eq "$(git -C "$R" tag --points-at HEAD)" "v1.0.1" "minor release tags HEAD"
assert_eq "$(cat "$R/VERSION")" "1.0.1" "minor release updates VERSION"
assert_contains "$(git -C "$R" log -1 --pretty=%B)" "feat: change" "release body lists squashed subject"
[[ "$(git -C "$R" rev-parse HEAD)" != "$(git -C "$R" rev-parse origin/main)" ]] && ok || bad "minor release did not push (--no-push)"

# 5. major bump math + v-prefix preservation
R="$(seed_release_repo major 1.2.3)"
run "$R" --bump major --yes --no-push
assert_eq "$(git -C "$R" log -1 --pretty=%s)" "Release v1.3.0" "major release subject"
assert_eq "$(cat "$R/VERSION")" "1.3.0" "major release updates VERSION"

# 6. duplicate commit subjects are deduplicated in the release body
R="$(seed_release_repo dedup)"
echo y > "$R/y.txt"; git -C "$R" add -A; git -C "$R" commit -qm "feat: same"
echo z > "$R/z.txt"; git -C "$R" add -A; git -C "$R" commit -qm "feat: same"
run "$R" --bump minor --yes --no-push
assert_eq "$(git -C "$R" log -1 --pretty=%B | grep -c 'feat: same')" "1" "duplicate subjects deduplicated"

# 7. all four version updaters fire
R="$(new_repo updaters)"
mkdir -p "$R/updaters"
printf '{\n  "name": "updaters",\n  "version": "1.0.0"\n}\n' > "$R/package.json"
printf '1.0.0\n' > "$R/VERSION"
printf '<?php\n/**\n * Plugin Name: Updaters\n * Version: 1.0.0\n */\n' > "$R/updaters/plugin.php"
printf '/*\nTheme Name: Updaters\nVersion: 1.0.0\n*/\n' > "$R/style.css"
git -C "$R" add -A; git -C "$R" commit -qm "chore: init"
git -C "$R" tag v1.0.0
git -C "$R" push -qu origin main >/dev/null 2>&1; git -C "$R" push -q origin v1.0.0
echo x > "$R/x.txt"; git -C "$R" add -A; git -C "$R" commit -qm "feat: x"
run "$R" --bump minor --yes --no-push
assert_contains "$(cat "$R/VERSION")" "1.0.1" "VERSION updated"
assert_contains "$(cat "$R/package.json")" '"version": "1.0.1"' "package.json version updated"
assert_contains "$(cat "$R/updaters/plugin.php")" "Version: 1.0.1" "plugin Version header updated"
assert_contains "$(cat "$R/style.css")" "Version: 1.0.1" "theme Version header updated"

# 8. squash-only: no version bump, no tag
R="$(seed_release_repo squashonly 2.0.0)"
TAGS_BEFORE="$(git -C "$R" tag | wc -l | tr -d ' ')"
run "$R" --squash --yes
assert_status "$STATUS" 0 "squash-only exits 0"
assert_contains "$(git -C "$R" log -1 --pretty=%s)" "Squash commits since v2.0.0" "squash-only subject"
assert_eq "$(git -C "$R" tag | wc -l | tr -d ' ')" "$TAGS_BEFORE" "squash-only creates no tag"
assert_eq "$(cat "$R/VERSION")" "2.0.0" "squash-only leaves VERSION unchanged"

# 9. --init: root commit plus one Initial commit
R="$(new_repo initmode)"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm "one"
echo b > "$R/b"; git -C "$R" add -A; git -C "$R" commit -qm "two"
echo c > "$R/c"; git -C "$R" add -A; git -C "$R" commit -qm "three"
git -C "$R" push -qu origin main >/dev/null 2>&1
run "$R" --init --yes
assert_status "$STATUS" 0 "--init exits 0"
assert_eq "$(git -C "$R" rev-list --count HEAD | tr -d ' ')" "2" "--init leaves root + Initial commit"
assert_eq "$(git -C "$R" log -1 --pretty=%s)" "Initial commit" "--init subject"

# 10. initial release (no tags) with --yes
R="$(new_repo firstrelease)"
printf '0.5.0\n' > "$R/VERSION"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm "one"
git -C "$R" push -qu origin main >/dev/null 2>&1
run "$R" --yes --no-push
assert_status "$STATUS" 0 "initial release exits 0"
assert_eq "$(git -C "$R" log -1 --pretty=%s)" "Release 0.0.1" "initial release subject"
assert_eq "$(git -C "$R" tag --points-at HEAD)" "0.0.1" "initial release tag"

# 11. version drift hard-stops; --allow-version-drift repairs from the tag
R="$(seed_release_repo mismatch 1.0.0)"
printf '9.9.9\n' > "$R/VERSION"
git -C "$R" add -A; git -C "$R" commit -qm "chore: bump VERSION"
HEAD_BEFORE="$(git -C "$R" rev-parse HEAD)"
TAGS_BEFORE="$(git -C "$R" tag | tr '\n' ' ')"

run "$R" --detect
assert_status "$STATUS" 1 "--detect fails on version drift"
assert_contains "$OUT" "Version drift: VERSION is 9.9.9 but the last tag is v1.0.0" "drift names path, value, and tag"

run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 1 "release fails on version drift"
assert_contains "$OUT" "Version drift blocks this release" "release explains the block"
assert_contains "$OUT" "Restore the premature version edits to 1.0.0" "remediation restores the tag value"
assert_contains "$OUT" "--allow-version-drift" "remediation names the escape hatch"
assert_eq "$(git -C "$R" rev-parse HEAD)" "$HEAD_BEFORE" "drift refusal leaves HEAD unchanged"
assert_eq "$(git -C "$R" tag | tr '\n' ' ')" "$TAGS_BEFORE" "drift refusal creates no tag"
assert_eq "$(git -C "$R" status --porcelain)" "" "drift refusal leaves a clean tree"
[[ ! -e "$R/plans/.pgf.release.lock" ]] && ok || bad "drift refusal creates no marker"

run "$R" --bump minor --yes --no-push --force
assert_status "$STATUS" 1 "--force does not bypass version drift"

run "$R" --bump minor --yes --no-push --allow-version-drift
assert_status "$STATUS" 0 "--allow-version-drift permits the release"
assert_contains "$OUT" "accepted via --allow-version-drift" "escape hatch is reported"
assert_eq "$(cat "$R/VERSION")" "1.0.1" "escape hatch rewrites VERSION from the tag"
assert_eq "$(git -C "$R" tag --points-at HEAD)" "v1.0.1" "escape hatch tags the tag-derived version"
assert_eq "$(git -C "$R" log -1 --pretty=%s)" "Release v1.0.1" "escape hatch release subject"

# 12. divergence guard
R="$(seed_release_repo divergence)"
git -C "$R" checkout -qb feature
echo f > "$R/f"; git -C "$R" add -A; git -C "$R" commit -qm "feat: f"
git -C "$R" push -qu origin feature >/dev/null 2>&1
git -C "$R" checkout -q main
echo m > "$R/m"; git -C "$R" add -A; git -C "$R" commit -qm "feat: m"
git -C "$R" push -q origin main >/dev/null 2>&1
git -C "$R" checkout -q feature
run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 1 "diverged branch blocks release"
assert_contains "$OUT" "diverged from origin/main" "divergence message printed"
run "$R" --bump minor --yes --no-push --skip-divergence-check
assert_status "$STATUS" 0 "--skip-divergence-check proceeds"

# 13. -r runs against another repo from elsewhere
R="$(seed_release_repo repoflag 3.0.0)"
run / -r "$R" --bump minor --yes --no-push
assert_status "$STATUS" 0 "-r exits 0"
assert_eq "$(git -C "$R" log -1 --pretty=%s)" "Release v3.0.1" "-r targets the given repo"

# 14. invalid --bump rejected
run / --bump huge
assert_status "$STATUS" 2 "invalid --bump exits 2"

# =============================================================================
# -- PGF integration: status, thresholds, locks, marker, mutation window
# =============================================================================

# 15. --status is the PGF gate's one-line contract and makes no changes
R="$(seed_release_repo statuskeys 1.2.3)"
printf '{"name":"x","version":"9.9.9"}\n' > "$R/package.json"
git -C "$R" add -A; git -C "$R" commit -qm "chore: package version"
BEFORE_HEAD="$(git -C "$R" rev-parse HEAD)"
BEFORE_TAGS="$(git -C "$R" tag | tr '\n' ' ')"
run "$R" --status
assert_status "$STATUS" 0 "--status exits 0"
assert_contains "$OUT" "VERSION: 9.9.9 (package.json)" "--status prefers package.json"
assert_contains "$OUT" "TAG: v1.2.3" "--status reports the latest tag"
assert_contains "$OUT" "MISMATCH: yes" "--status reports a mismatch"
assert_contains "$OUT" "ACTION: release" "--status reports the release action"
assert_contains "$OUT" "SQUASH: no" "--status reports the squash verdict"
assert_eq "$(git -C "$R" rev-parse HEAD)" "$BEFORE_HEAD" "--status leaves HEAD unchanged"
assert_eq "$(git -C "$R" tag | tr '\n' ' ')" "$BEFORE_TAGS" "--status creates no tag"
[[ ! -e "$R/plans/.pgf.release.lock" ]] && ok || bad "--status creates no release marker"

R="$(new_repo statusnoversion)"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm "chore: init"
git -C "$R" push -qu origin main >/dev/null 2>&1
run "$R" --status
assert_contains "$OUT" "VERSION: none" "no version source reports none"
assert_contains "$OUT" "MISMATCH: no" "no version source is not a mismatch"
assert_contains "$OUT" "SQUASH: no" "no version source never recommends a squash"

# 16. squash threshold precedence: env > plans/pgf.config > 20
R="$(seed_release_repo thresholds 2.0.0)"
for i in $(seq 1 19); do git -C "$R" commit -q --allow-empty -m "feat: c$i"; done
git -C "$R" push -q origin main
run "$R" --status
assert_contains "$OUT" "COMMITS: 20" "status counts commits since the tag"
assert_contains "$OUT" "SQUASH: yes" "20 reaches the default threshold"
git -C "$R" commit -q --allow-empty -m "feat: c20"; git -C "$R" push -q origin main
run "$R" --status
assert_contains "$OUT" "COMMITS: 21" "status counts 21 commits"
assert_contains "$OUT" "SQUASH: yes" "21 reaches the default threshold"
OUT="$(cd "$R" && PGF_SQUASH_THRESHOLD=25 bash "$SCRIPT" --status 2>&1)"; STATUS=$?
assert_contains "$OUT" "SQUASH: no" "env threshold raises the bar"
mkdir -p "$R/plans"
printf 'SQUASH_THRESHOLD=25\n' > "$R/plans/pgf.config"
git -C "$R" add -A; git -C "$R" commit -qm "chore: set squash threshold"
run "$R" --status
assert_contains "$OUT" "SQUASH: no" "config threshold raises the bar"
OUT="$(cd "$R" && PGF_SQUASH_THRESHOLD=5 bash "$SCRIPT" --status 2>&1)"; STATUS=$?
assert_contains "$OUT" "SQUASH: yes" "env threshold wins over config"
OUT="$(cd "$R" && PGF_SQUASH_THRESHOLD=abc bash "$SCRIPT" --status 2>&1)"; STATUS=$?
assert_contains "$OUT" "Invalid squash threshold" "invalid override warns"
assert_contains "$OUT" "SQUASH: yes" "invalid override falls back to 20"
printf 'SQUASH_THRESHOLD="15"\n' > "$R/plans/pgf.config"
run "$R" --status
assert_contains "$OUT" "SQUASH: yes" "quoted config value is parsed"

# 17. PGF execution lock gate
R="$(seed_release_repo lockgate)"
mkdir -p "$R/plans"
printf '# demo\n\n**Version:** 5\n**Status:** Not Started\n**Type:** fix\n' > "$R/plans/demo.md"
printf 'plans/.pgf.lock\nplans/.pgf.release.lock\n' > "$R/.gitignore"
git -C "$R" add -A; git -C "$R" commit -qm "chore: add plans"
git -C "$R" push -q origin main
HEAD_BEFORE="$(git -C "$R" rev-parse HEAD)"
TAGS_BEFORE="$(git -C "$R" tag | tr '\n' ' ')"
printf 'PGF_LOCK_VERSION=1\nPLAN=demo\nPLAN_FILE=%s/plans/demo.md\nOWNER=me\nHOST=here\nPID=1\nSTARTED=2026-01-01T00:00:00Z\n' "$R" > "$R/plans/.pgf.lock"

run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 1 "release refuses a held plan lock"
assert_contains "$OUT" "[FAIL] No PGF execution lock held (plan demo" "lock refusal names the plan"
assert_contains "$OUT" "pgf unlock demo" "lock refusal prints the unlock remedy"
assert_contains "$OUT" "--ignore-pgf-lock" "lock refusal prints the override flag"
assert_eq "$(git -C "$R" rev-parse HEAD)" "$HEAD_BEFORE" "refused release left HEAD unchanged"
assert_eq "$(git -C "$R" tag | tr '\n' ' ')" "$TAGS_BEFORE" "refused release created no tag"
[[ ! -e "$R/plans/.pgf.release.lock" ]] && ok || bad "refused release left no marker"

run "$R" --status
assert_status "$STATUS" 0 "--status works while a lock is held"
assert_contains "$OUT" "VERSION: 1.0.0" "--status still reports the version"

run "$R" --detect
assert_status "$STATUS" 1 "--detect reports a held plan lock"
assert_contains "$OUT" "No PGF execution lock held (plan demo" "--detect names the held plan"

run "$R" --bump minor --yes --no-push --ignore-pgf-lock
assert_status "$STATUS" 0 "--ignore-pgf-lock allows the release"
assert_contains "$OUT" "ignored via --ignore-pgf-lock" "override is reported"
assert_eq "$(cat "$R/VERSION")" "1.0.1" "override released 1.0.1"
rm -f "$R/plans/.pgf.lock"

printf 'garbage\n' > "$R/plans/.pgf.lock"
run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 1 "release refuses a malformed plan lock"
assert_contains "$OUT" "malformed lock" "malformed refusal says malformed"
assert_contains "$OUT" "pgf unlock --force" "malformed refusal prints the force remedy"
rm -f "$R/plans/.pgf.lock"

# 18. release marker lifecycle
R="$(seed_release_repo markerok)"
mkdir -p "$R/plans"
printf 'plans/.pgf.lock\nplans/.pgf.release.lock\n' > "$R/.gitignore"
git -C "$R" add -A; git -C "$R" commit -qm "chore: add plans"
git -C "$R" push -q origin main
printf '#!/usr/bin/env bash\ncp plans/.pgf.release.lock %s/witness-markerok 2>/dev/null || true\n' "$TMPROOT" > "$R/.git/hooks/pre-commit"
chmod +x "$R/.git/hooks/pre-commit"
run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 0 "release with a plans dir succeeds"
assert_contains "$OUT" "[OK] Release lock acquired" "release reports the acquired marker"
assert_contains "$OUT" "[OK] Release lock released" "release reports the removed marker"
[[ -f "$TMPROOT/witness-markerok" ]] && ok || bad "marker exists during the bump commit"
[[ ! -e "$R/plans/.pgf.release.lock" ]] && ok || bad "marker removed after a successful release"
rm -f "$R/.git/hooks/pre-commit"

R="$(seed_release_repo markerbusy)"
mkdir -p "$R/plans"
printf 'plans/.pgf.lock\nplans/.pgf.release.lock\n' > "$R/.gitignore"
git -C "$R" add -A; git -C "$R" commit -qm "chore: add plans"
git -C "$R" push -q origin main
HEAD_BEFORE="$(git -C "$R" rev-parse HEAD)"
printf 'PGF_RELEASE_LOCK_VERSION=1\nKIND=release\nREPO=demo\nOWNER=me\nHOST=here\nPID=999999\nSTARTED=2026-01-01T00:00:00Z\nHEAD=%s\n' "$HEAD_BEFORE" > "$R/plans/.pgf.release.lock"
run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 1 "release refuses a pre-existing marker"
assert_contains "$OUT" "A release is already in progress: demo" "marker refusal names the holder"
assert_eq "$(git -C "$R" rev-parse HEAD)" "$HEAD_BEFORE" "marker refusal left HEAD unchanged"
[[ -e "$R/plans/.pgf.release.lock" ]] && ok || bad "marker refusal does not remove the foreign marker"
rm -f "$R/plans/.pgf.release.lock"
run "$R" --status
[[ ! -e "$R/plans/.pgf.release.lock" ]] && ok || bad "--status creates no marker"
run "$R" --detect
[[ ! -e "$R/plans/.pgf.release.lock" ]] && ok || bad "--detect creates no marker"

R="$(seed_release_repo markerfail)"
mkdir -p "$R/plans"
printf 'plans/.pgf.lock\nplans/.pgf.release.lock\n' > "$R/.gitignore"
git -C "$R" add -A; git -C "$R" commit -qm "chore: add plans"
git -C "$R" push -q origin main
printf '#!/usr/bin/env bash\nexit 1\n' > "$R/.git/hooks/pre-commit"
chmod +x "$R/.git/hooks/pre-commit"
run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 1 "a failing hook fails the release"
[[ ! -e "$R/plans/.pgf.release.lock" ]] && ok || bad "marker removed after a failed release"
rm -f "$R/.git/hooks/pre-commit"

R="$(seed_release_repo markerprompt)"
mkdir -p "$R/plans"
printf 'plans/.pgf.lock\nplans/.pgf.release.lock\n' > "$R/.gitignore"
git -C "$R" add -A; git -C "$R" commit -qm "chore: add plans"
git -C "$R" push -q origin main
OUT="$(cd "$R" && bash "$SCRIPT" --bump minor </dev/null 2>&1)"; STATUS=$?
assert_status "$STATUS" 2 "non-TTY without --yes fails"
[[ ! -e "$R/plans/.pgf.release.lock" ]] && ok || bad "marker removed after the prompt path fails"

# 19. mutation window guards
R="$(seed_release_repo mutmerge)"
mkdir -p "$R/plans"
printf 'plans/.pgf.lock\nplans/.pgf.release.lock\n' > "$R/.gitignore"
git -C "$R" add -A; git -C "$R" commit -qm "chore: add plans"
git -C "$R" push -q origin main
HEAD_BEFORE="$(git -C "$R" rev-parse HEAD)"
touch "$R/.git/MERGE_HEAD"
run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 1 "release refuses a merge in progress"
assert_contains "$OUT" "git operation is in progress (MERGE_HEAD)" "recheck names the merge state"
assert_eq "$(git -C "$R" rev-parse HEAD)" "$HEAD_BEFORE" "merge abort left HEAD unchanged"
[[ ! -e "$R/plans/.pgf.release.lock" ]] && ok || bad "merge abort released the marker"
rm -f "$R/.git/MERGE_HEAD"

R="$(seed_release_repo mutcommit)"
mkdir -p "$R/plans"
printf 'plans/.pgf.lock\nplans/.pgf.release.lock\n' > "$R/.gitignore"
git -C "$R" add -A; git -C "$R" commit -qm "chore: add plans"
git -C "$R" push -q origin main
FLAG="$TMPROOT/mutcommit.flag"
printf '#!/usr/bin/env bash\n[[ -e %s ]] && exit 0\ntouch %s\nprintf "concurrent\\n" > concurrent.txt\ngit add concurrent.txt\ngit commit -qm "concurrent commit"\n' "$FLAG" "$FLAG" > "$R/.git/hooks/post-commit"
chmod +x "$R/.git/hooks/post-commit"
run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 1 "concurrent commit aborts the release"
assert_contains "$OUT" "A commit landed during the release" "recheck reports the concurrent commit"
[[ -z $(git -C "$R" tag -l v1.0.1) ]] && ok || bad "concurrent abort created no tag"
git -C "$R" log --all --format=%s | grep -qx 'concurrent commit' && ok || bad "concurrent commit is still reachable"
[[ ! -e "$R/plans/.pgf.release.lock" ]] && ok || bad "concurrent abort released the marker"
rm -f "$R/.git/hooks/post-commit"

R="$(seed_release_repo mutindex)"
mkdir -p "$R/plans"
printf 'plans/.pgf.lock\nplans/.pgf.release.lock\n' > "$R/.gitignore"
git -C "$R" add -A; git -C "$R" commit -qm "chore: add plans"
git -C "$R" push -q origin main
FLAG="$TMPROOT/mutindex.flag"
printf '#!/usr/bin/env bash\n[[ -e %s ]] && exit 0\ntouch %s\ntouch "$(git rev-parse --git-dir)/index.lock"\n' "$FLAG" "$FLAG" > "$R/.git/hooks/post-commit"
chmod +x "$R/.git/hooks/post-commit"
run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 1 "locked index aborts the release"
assert_contains "$OUT" "git index is locked" "recheck reports the locked index"
[[ -z $(git -C "$R" tag -l v1.0.1) ]] && ok || bad "index abort created no tag"
rm -f "$R/.git/hooks/post-commit" "$(git -C "$R" rev-parse --git-dir)/index.lock"

R="$(seed_release_repo mutpre)"
mkdir -p "$R/plans"
printf 'plans/.pgf.lock\nplans/.pgf.release.lock\n' > "$R/.gitignore"
git -C "$R" add -A; git -C "$R" commit -qm "chore: add plans"
git -C "$R" push -q origin main
HEAD_BEFORE="$(git -C "$R" rev-parse HEAD)"
printf '#!/usr/bin/env bash\nexit 1\n' > "$R/.git/hooks/pre-commit"
chmod +x "$R/.git/hooks/pre-commit"
run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 1 "a failing bump commit aborts the release"
assert_eq "$(git -C "$R" rev-parse HEAD)" "$HEAD_BEFORE" "failed bump left HEAD at the saved head"
assert_eq "$(git -C "$R" status --porcelain)" "" "failed bump left a clean working tree"
[[ -z $(git -C "$R" tag -l v1.0.1) ]] && ok || bad "failed bump created no tag"
assert_contains "$OUT" "restored the repository to" "failed bump reports the restore"
rm -f "$R/.git/hooks/pre-commit"

R="$(seed_release_repo mutclean)"
mkdir -p "$R/plans"
printf 'plans/.pgf.lock\nplans/.pgf.release.lock\n' > "$R/.gitignore"
git -C "$R" add -A; git -C "$R" commit -qm "chore: add plans"
git -C "$R" push -q origin main
run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 0 "clean release still succeeds"
assert_eq "$(git -C "$R" rev-list --count v1.0.0..HEAD | tr -d ' ')" "1" "clean release produced one commit"
assert_eq "$(git -C "$R" tag | wc -l | tr -d ' ')" "2" "clean release produced one new tag"

# 20. taken target tag is refused before any mutation
R="$(seed_release_repo takentag)"
EMPTY_TREE="$(git -C "$R" hash-object -t tree /dev/null)"
DANGLING="$(git -C "$R" commit-tree "$EMPTY_TREE" -m "stale release")"
git -C "$R" tag v1.0.1 "$DANGLING"
HEAD_BEFORE="$(git -C "$R" rev-parse HEAD)"
run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 2 "taken tag refuses the release"
assert_contains "$OUT" "Tag v1.0.1 already exists" "refusal names the taken tag"
assert_contains "$OUT" "git tag -d v1.0.1" "refusal names the removal remedy"
assert_eq "$(git -C "$R" rev-parse HEAD)" "$HEAD_BEFORE" "refusal leaves HEAD untouched"
assert_eq "$(cat "$R/VERSION")" "1.0.0" "refusal leaves VERSION untouched"
assert_eq "$(git -C "$R" rev-list --count v1.0.0..HEAD)" "1" "refusal leaves history unsquashed"
[[ ! -e "$R/plans/.pgf.release.lock" ]] && ok || bad "refusal leaves no marker"

# 21. every writable source participates in drift checking
R="$(new_repo driftsecondary)"
printf '2.0.0\n' > "$R/VERSION"
printf '{\n  "name": "d",\n  "version": "2.0.0"\n}\n' > "$R/package.json"
git -C "$R" add -A; git -C "$R" commit -qm "chore: init"
git -C "$R" tag v2.0.0
git -C "$R" push -qu origin main >/dev/null 2>&1; git -C "$R" push -q origin v2.0.0
printf '1.9.0\n' > "$R/VERSION"
git -C "$R" add -A; git -C "$R" commit -qm "chore: drift VERSION only"
HEAD_BEFORE="$(git -C "$R" rev-parse HEAD)"
run "$R" --status
assert_contains "$OUT" "MISMATCH: yes" "status reports secondary drift"
run "$R" --detect
assert_status "$STATUS" 1 "detect catches VERSION drift under a matching package.json"
assert_contains "$OUT" "Version drift: VERSION is 1.9.0 but the last tag is v2.0.0" "secondary drift names VERSION"
run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 1 "release refuses secondary drift"
assert_eq "$(git -C "$R" rev-parse HEAD)" "$HEAD_BEFORE" "secondary drift refusal leaves HEAD unchanged"
assert_eq "$(git -C "$R" status --porcelain)" "" "secondary drift refusal leaves a clean tree"

R="$(new_repo driftplugin)"
mkdir -p "$R/driftplugin"
printf '1.0.0\n' > "$R/VERSION"
printf '<?php\n/**\n * Plugin Name: Drift\n * Version: 1.0.0\n */\n' > "$R/driftplugin/plugin.php"
printf '/*\nTheme Name: Drift\nVersion: 1.0.0\n*/\n' > "$R/style.css"
git -C "$R" add -A; git -C "$R" commit -qm "chore: init"
git -C "$R" tag v1.0.0
git -C "$R" push -qu origin main >/dev/null 2>&1; git -C "$R" push -q origin v1.0.0
sed -i 's/Version: 1.0.0/Version: 0.9.9/' "$R/driftplugin/plugin.php"
git -C "$R" add -A; git -C "$R" commit -qm "chore: drift plugin header"
run "$R" --detect
assert_status "$STATUS" 1 "detect catches a drifting plugin header"
assert_contains "$OUT" "Version drift: ./driftplugin/plugin.php is 0.9.9" "plugin drift names the header path"
git -C "$R" checkout -q -- driftplugin/plugin.php
sed -i 's/^Version: .*/Version: 0.8.0/' "$R/style.css"
git -C "$R" add -A; git -C "$R" commit -qm "chore: drift theme header"
run "$R" --detect
assert_status "$STATUS" 1 "detect catches a drifting theme header"
assert_contains "$OUT" "Version drift: ./style.css is 0.8.0" "theme drift names the header path"

R="$(new_repo driftnov)"
printf '1.0.0\n' > "$R/VERSION"
git -C "$R" add -A; git -C "$R" commit -qm "chore: init"
git -C "$R" tag 1.0.0
git -C "$R" push -qu origin main >/dev/null 2>&1; git -C "$R" push -q origin 1.0.0
printf 'x\n' > "$R/x.txt"; git -C "$R" add -A; git -C "$R" commit -qm "feat: x"
run "$R" --detect
assert_status "$STATUS" 0 "an unprefixed tag is accepted"
run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 0 "release works from an unprefixed tag"
assert_eq "$(cat "$R/VERSION")" "1.0.1" "unprefixed release bumps the patch"
assert_eq "$(git -C "$R" tag --points-at HEAD)" "1.0.1" "unprefixed tag has no v prefix"
assert_eq "$(git -C "$R" log -1 --pretty=%s)" "Release 1.0.1" "unprefixed release subject"

R="$(seed_release_repo driftmalformed 1.0.0)"
printf 'abc\n' > "$R/VERSION"
git -C "$R" add -A; git -C "$R" commit -qm "chore: malformed version"
HEAD_BEFORE="$(git -C "$R" rev-parse HEAD)"
run "$R" --detect
assert_status "$STATUS" 1 "detect fails a malformed version"
assert_contains "$OUT" "malformed version 'abc'" "malformed value is named"
run "$R" --bump minor --yes --no-push --allow-version-drift
assert_status "$STATUS" 1 "--allow-version-drift does not accept a malformed value"
assert_contains "$OUT" "does not accept malformed values" "malformed refusal explains the limit"
assert_eq "$(cat "$R/VERSION")" "abc" "malformed refusal leaves VERSION untouched"
assert_eq "$(git -C "$R" rev-parse HEAD)" "$HEAD_BEFORE" "malformed refusal leaves HEAD unchanged"

R="$(new_repo driftonlycomposer)"
printf '{\n  "name": "c",\n  "version": "1.0.0"\n}\n' > "$R/composer.json"
git -C "$R" add -A; git -C "$R" commit -qm "chore: init"
git -C "$R" tag v1.0.0
git -C "$R" push -qu origin main >/dev/null 2>&1; git -C "$R" push -q origin v1.0.0
printf 'x\n' > "$R/x.txt"; git -C "$R" add -A; git -C "$R" commit -qm "feat: x"; git -C "$R" push -q origin main
run "$R" --status
assert_contains "$OUT" "VERSION: 1.0.0 (composer.json (detection only))" "status reports a detection-only source"
run "$R" --detect
assert_status "$STATUS" 0 "detection-only source passes detection"
HEAD_BEFORE="$(git -C "$R" rev-parse HEAD)"
run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 1 "release refuses a detection-only version source"
assert_contains "$OUT" "No writable version source found" "refusal names the missing writable source"
assert_eq "$(git -C "$R" rev-parse HEAD)" "$HEAD_BEFORE" "detection-only refusal leaves HEAD unchanged"
[[ -z $(git -C "$R" tag -l v1.0.1) ]] && ok || bad "detection-only refusal created no tag"

R="$(new_repo driftallmatch)"
mkdir -p "$R/driftallmatch"
printf '3.4.5\n' > "$R/VERSION"
printf '{\n  "name": "m",\n  "version": "3.4.5"\n}\n' > "$R/package.json"
printf '<?php\n/**\n * Plugin Name: Match\n * Version: 3.4.5\n */\n' > "$R/driftallmatch/plugin.php"
printf '/*\nTheme Name: Match\nVersion: 3.4.5\n*/\n' > "$R/style.css"
git -C "$R" add -A; git -C "$R" commit -qm "chore: init"
git -C "$R" tag v3.4.5
git -C "$R" push -qu origin main >/dev/null 2>&1; git -C "$R" push -q origin v3.4.5
printf 'x\n' > "$R/x.txt"; git -C "$R" add -A; git -C "$R" commit -qm "feat: x"
run "$R" --detect
assert_status "$STATUS" 0 "all writable sources matching the tag pass detection"
run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 0 "all-matching release succeeds"
assert_eq "$(cat "$R/VERSION")" "3.4.6" "matching release updates VERSION"
assert_contains "$(cat "$R/package.json")" '"version": "3.4.6"' "matching release updates package.json"
assert_contains "$(cat "$R/driftallmatch/plugin.php")" "Version: 3.4.6" "matching release updates the plugin header"
assert_contains "$(cat "$R/style.css")" "Version: 3.4.6" "matching release updates the theme header"

# =============================================================================
# -- Claude package tests (local additions)

# A release updates VERSION, plugin.json, and both marketplace version fields,
# then promotes the changelog's Unreleased section.
R="$(new_repo claudemanifests)"
printf '1.0.0\n' > "$R/VERSION"
mkdir -p "$R/.claude-plugin"
printf '{\n  "name": "demo",\n  "version": "1.0.0"\n}\n' > "$R/.claude-plugin/plugin.json"
printf '{\n  "name": "demo-market",\n  "version": "1.0.0",\n  "owner": {\n    "name": "tester"\n  },\n  "plugins": [\n    {\n      "name": "demo",\n      "source": "./",\n      "version": "1.0.0"\n    }\n  ]\n}\n' > "$R/.claude-plugin/marketplace.json"
printf '# Changelog\n\n## Unreleased\n\n### Added\n\n- A thing.\n\n## v1.0.0 - 2026-01-01\n\n- Older.\n' > "$R/CHANGELOG.md"
git -C "$R" add -A; git -C "$R" commit -qm "chore: init"
git -C "$R" tag v1.0.0
git -C "$R" push -qu origin main >/dev/null 2>&1; git -C "$R" push -q origin v1.0.0
printf 'x\n' > "$R/x.txt"; git -C "$R" add -A; git -C "$R" commit -qm "feat: x"
run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 0 "release with Claude manifests exits 0"
assert_eq "$(cat "$R/VERSION")" "1.0.1" "Claude release updates VERSION"
assert_contains "$(cat "$R/.claude-plugin/plugin.json")" '"version": "1.0.1"' "Claude release updates plugin.json"
assert_contains "$(cat "$R/.claude-plugin/marketplace.json")" '"version": "1.0.1"' "Claude release updates the marketplace version"
assert_eq "$(python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); print(m["version"], m["plugins"][0]["version"])' "$R/.claude-plugin/marketplace.json")" "1.0.1 1.0.1" "Claude release updates the marketplace entry"
TODAY="$(date +%Y-%m-%d)"
assert_contains "$(cat "$R/CHANGELOG.md")" "## v1.0.1 - $TODAY" "release promotes the changelog section"
assert_contains "$(cat "$R/CHANGELOG.md")" "- A thing." "promoted changelog keeps its content"
assert_eq "$(sed -n '1,6p' "$R/CHANGELOG.md" | grep -c '^## Unreleased$')" "1" "release leaves one Unreleased heading"
assert_eq "$(grep -c '^## v1.0.0' "$R/CHANGELOG.md")" "1" "release keeps the older section"

# Drift across the marketplace entry blocks a release.
R="$(seed_release_repo claudedrift)"
mkdir -p "$R/.claude-plugin"
printf '{\n  "name": "demo",\n  "version": "1.0.0"\n}\n' > "$R/.claude-plugin/plugin.json"
printf '{\n  "name": "demo-market",\n  "version": "1.0.0",\n  "owner": {\n    "name": "tester"\n  },\n  "plugins": [\n    {\n      "name": "demo",\n      "source": "./",\n      "version": "0.9.0"\n    }\n  ]\n}\n' > "$R/.claude-plugin/marketplace.json"
git -C "$R" add -A; git -C "$R" commit -qm "chore: add manifests"
run "$R" --detect
assert_status "$STATUS" 1 "mismatched marketplace entry fails detection"
assert_contains "$OUT" "MISMATCH" "mismatched marketplace entry is reported"

# A malformed manifest blocks the release without partial edits.
R="$(seed_release_repo claudemalformed)"
mkdir -p "$R/.claude-plugin"
printf '{"name": "demo", "version": "1.0.0"\n' > "$R/.claude-plugin/plugin.json"
git -C "$R" add -A; git -C "$R" commit -qm "chore: add malformed manifest"
HEAD_BEFORE="$(git -C "$R" rev-parse HEAD)"
run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 1 "malformed plugin manifest blocks the release"
assert_eq "$(cat "$R/VERSION")" "1.0.0" "malformed manifest leaves VERSION untouched"
assert_eq "$(git -C "$R" rev-parse HEAD)" "$HEAD_BEFORE" "malformed manifest leaves HEAD unchanged"

# An empty Unreleased section is left alone.
R="$(seed_release_repo changelogempty)"
printf '# Changelog\n\n## Unreleased\n\n## v1.0.0 - 2026-01-01\n\n- Older.\n' > "$R/CHANGELOG.md"
git -C "$R" add -A; git -C "$R" commit -qm "docs: changelog"
run "$R" --bump minor --yes --no-push
assert_status "$STATUS" 0 "empty Unreleased section does not block the release"
assert_eq "$(grep -c '^## v1.0.1' "$R/CHANGELOG.md")" "0" "empty Unreleased section adds no release heading"

# =============================================================================
printf 'pass: %d  fail: %d\n' "$PASS" "$FAIL"
if [[ $FAIL -eq 0 ]]; then
    printf 'OK\n'
    exit 0
fi
printf 'FAILED\n'
exit 1
