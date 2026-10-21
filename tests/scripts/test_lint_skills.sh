#!/usr/bin/env bash
#
# test_lint_skills.sh - offline tests for scripts/lint-skills.sh frontmatter
# and npx skills discovery rules.
#
# Checks the current tree plus fixtures for the metadata.internal rule:
# `_`-prefixed scaffolds must carry it, real skills must not.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LINT="$REPO_ROOT/scripts/lint-skills.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ok() { printf 'ok: %s\n' "$1"; }

[[ -x "$LINT" ]] || fail "linter not executable: $LINT"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

skill_md() {
    local path="$1" name="$2" marker="${3:-}"
    mkdir -p "$(dirname "$path")"
    {
        printf -- '---\n'
        printf 'name: %s\n' "$name"
        printf 'description: Fixture skill for the lint rule.\n'
        [[ -n "$marker" ]] && printf 'metadata:\n  internal: true\n'
        printf -- '---\n\n# %s\n' "$name"
    } >"$path"
}

# 1. The repository itself passes.
"$LINT" >/dev/null 2>&1 || fail "lint-skills.sh fails on the repository"
ok "repository passes lint"

# 2. A real skill without the marker passes.
skill_md "$WORK/plain/skills/alpha/SKILL.md" alpha
"$LINT" "$WORK/plain/skills" >/dev/null 2>&1 || fail "plain skill was rejected"
ok "plain skill passes"

# 3. A real skill carrying metadata.internal is rejected.
skill_md "$WORK/hidden/skills/alpha/SKILL.md" alpha marker
if "$LINT" "$WORK/hidden/skills" >"$WORK/hidden.out" 2>&1; then
    fail "real skill with metadata.internal was accepted"
fi
grep -q 'hides a real skill' "$WORK/hidden.out" || fail "missing hidden-skill error message"
ok "real skill with metadata.internal is rejected"

# 4. A scaffold without the marker is rejected.
skill_md "$WORK/scaffold-bare/skills/_scaffold/SKILL.md" scaffold
if "$LINT" "$WORK/scaffold-bare/skills" >"$WORK/scaffold-bare.out" 2>&1; then
    fail "scaffold without metadata.internal was accepted"
fi
grep -q 'scaffold must set' "$WORK/scaffold-bare.out" || fail "missing scaffold error message"
ok "scaffold without metadata.internal is rejected"

# 5. A scaffold with the marker passes and is not treated as a real skill.
skill_md "$WORK/scaffold-ok/skills/_scaffold/SKILL.md" scaffold marker
"$LINT" "$WORK/scaffold-ok/skills" >/dev/null 2>&1 || fail "scaffold with metadata.internal was rejected"
ok "scaffold with metadata.internal passes"

printf 'All lint-skills tests passed.\n'
