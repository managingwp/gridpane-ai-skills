#!/usr/bin/env bash
#
# test_lint_skills.sh - offline tests for scripts/lint-skills.sh.
#
# Checks the current tree plus fixtures for the claude.ai frontmatter rules
# (name grammar/folder match, 200-character description), the package-path
# rule, and the plugin manifests' skill list.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LINT="$REPO_ROOT/scripts/lint-skills.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ok() { printf 'ok: %s\n' "$1"; }

[[ -x "$LINT" ]] || fail "linter not executable: $LINT"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# skill_md <path> <name> <description> [body]
# An empty name or description omits that frontmatter key on purpose.
skill_md() {
    local path="$1" name="$2" desc="$3" body="${4:-}"
    mkdir -p "$(dirname "$path")"
    {
        printf -- '---\n'
        [[ -n "$name" ]] && printf 'name: %s\n' "$name"
        if [[ -n "$desc" ]]; then
            printf 'description: >-\n'
            printf '%s\n' "$desc" | fold -s -w 70 | sed 's/^/  /'
        fi
        printf -- '---\n\n# %s\n' "${name:-skill}"
        [[ -n "$body" ]] && printf '\n%s\n' "$body"
    } >"$path"
    return 0
}

expect_fail() { # <label> <dir> <expected message fragment>
    local label="$1" dir="$2" needle="$3"
    local out
    out="$WORK/$(printf '%s' "$label" | tr -c 'A-Za-z0-9._-' '-').out"
    if "$LINT" "$dir" >"$out" 2>&1; then
        fail "$label was accepted"
    fi
    grep -qF "$needle" "$out" || fail "$label: missing message '$needle'"
    ok "$label is rejected"
}

# 1. The repository itself passes.
"$LINT" >/dev/null 2>&1 || fail "lint-skills.sh fails on the repository"
ok "repository passes lint"

# 2. A valid skill passes.
skill_md "$WORK/plain/skills/alpha/SKILL.md" alpha "Use when testing a fixture skill."
"$LINT" "$WORK/plain/skills" >/dev/null 2>&1 || fail "valid skill was rejected"
ok "valid skill passes"

# 3. Name grammar and folder match.
skill_md "$WORK/upper/skills/Alpha/SKILL.md" Alpha "Valid description."
expect_fail "uppercase name" "$WORK/upper/skills" "lowercase letters, digits and single hyphens"

skill_md "$WORK/mismatch/skills/alpha/SKILL.md" beta "Valid description."
expect_fail "name/folder mismatch" "$WORK/mismatch/skills" "does not match folder"

skill_md "$WORK/no-name/skills/alpha/SKILL.md" "" "Valid description."
expect_fail "missing name" "$WORK/no-name/skills" "missing required frontmatter field 'name'"

# 4. Description presence and the 200-character claude.ai limit.
skill_md "$WORK/no-desc/skills/alpha/SKILL.md" alpha ""
expect_fail "missing description" "$WORK/no-desc/skills" "missing required frontmatter field 'description'"

desc_201="$(python3 -c 'print(("word " * 50)[:201])')"
skill_md "$WORK/long/skills/alpha/SKILL.md" alpha "$desc_201"
expect_fail "201-character description" "$WORK/long/skills" "> 200 claude.ai limit"

desc_200="$(python3 -c 'print(("word " * 50)[:200])')"
skill_md "$WORK/exact/skills/alpha/SKILL.md" alpha "$desc_200"
"$LINT" "$WORK/exact/skills" >/dev/null 2>&1 || fail "200-character description was rejected"
ok "200-character description passes"

# 5. Package paths: no absolute links or workstation paths.
skill_md "$WORK/abs-link/skills/alpha/SKILL.md" alpha "Valid description." "Read [the core docs](/etc/nginx)."
expect_fail "absolute markdown link" "$WORK/abs-link/skills" "absolute package link"

skill_md "$WORK/home/skills/alpha/SKILL.md" alpha "Valid description." "Run the copy from /home/user/gridpane-ai-skills."
expect_fail "workstation /home path" "$WORK/home/skills" "workstation absolute path"

skill_md "$WORK/users/skills/alpha/SKILL.md" alpha "Valid description." "Run the copy from /Users/user/gridpane-ai-skills."
expect_fail "workstation /Users path" "$WORK/users/skills" "workstation absolute path"

# Documented GridPane server paths stay allowed, and https:// is not a drive path.
skill_md "$WORK/server-paths/skills/alpha/SKILL.md" alpha "Valid description." \
    "Paths: /etc/nginx, /var/www/example.com, /usr/local/bin/gp, /root/gridenv. Docs: https://gridpane.com/kb/."
"$LINT" "$WORK/server-paths/skills" >/dev/null 2>&1 || fail "GridPane server paths were rejected"
ok "GridPane server paths pass"

# 6. The Claude plugin exposes exactly the production skills, and never the template.
python3 - "$REPO_ROOT" <<'PY' || exit 1
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
plugin = json.loads((root / ".claude-plugin/plugin.json").read_text())
marketplace = json.loads((root / ".claude-plugin/marketplace.json").read_text())
expected = sorted(p.parent.name for p in (root / "skills").glob("gridpane-*/SKILL.md"))
declared = sorted(pathlib.PurePosixPath(p).name for p in plugin["skills"])
assert declared == expected, f"plugin skills {declared} != {expected}"
assert plugin["name"] == "gridpane"
assert [p["name"] for p in marketplace["plugins"]] == ["gridpane"]
entry = marketplace["plugins"][0]
assert entry["source"] == "./", entry["source"]
blob = json.dumps(plugin) + json.dumps(marketplace)
for false_name in ("gridpane-example", "templates/skill", "_template"):
    assert false_name not in blob, false_name
PY
ok "plugin manifests expose exactly the production skills"

printf 'All lint-skills tests passed.\n'
