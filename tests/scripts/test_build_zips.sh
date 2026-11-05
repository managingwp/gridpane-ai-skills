#!/usr/bin/env bash
#
# test_build_zips.sh - offline tests for scripts/build-zips.sh.
#
# Builds a small fixture repository in a temp directory and checks the archive
# layout, the vendored and rewritten cross-skill references, the excluded dev
# files and template, failure on a name/folder mismatch, the byte limit, and
# repeatable output. The repository itself is then built once into a temp
# directory to confirm the real skill set.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD="$REPO_ROOT/scripts/build-zips.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ok() { printf 'ok: %s\n' "$1"; }

[[ -x "$BUILD" ]] || fail "build script not executable: $BUILD"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FIXTURE="$WORK/fixture"
mkdir -p "$FIXTURE/scripts"
cp "$BUILD" "$FIXTURE/scripts/build-zips.sh"

skill_md() { # <path> <name> <body>
    local path="$1" name="$2" body="${3:-}"
    mkdir -p "$(dirname "$path")"
    {
        printf -- '---\nname: %s\n' "$name"
        printf 'description: Fixture skill for the archive build.\n'
        printf -- '---\n\n# %s\n' "$name"
        [[ -n "$body" ]] && printf '\n%s\n' "$body"
    } >"$path"
    return 0
}

# --- fixture ---------------------------------------------------------------

skill_md "$FIXTURE/skills/gridpane-core/SKILL.md" gridpane-core \
    "Read \`gridpane-api/references/endpoints.md\` for the API contract."
mkdir -p "$FIXTURE/skills/gridpane-core/references"
printf '# safety\n\nFixture safety protocol.\n' >"$FIXTURE/skills/gridpane-core/references/safety.md"
printf '# paths\n\nFixture paths.\n' >"$FIXTURE/skills/gridpane-core/references/paths.md"
printf '# gp conventions\n\nFixture gp conventions.\n' >"$FIXTURE/skills/gridpane-core/references/gp-conventions.md"
printf '# sources\n\nSee gridpane-api/references/endpoints.md.\n' >"$FIXTURE/skills/gridpane-core/references/sources.md"

skill_md "$FIXTURE/skills/gridpane-api/SKILL.md" gridpane-api \
    "Read \`gridpane-core/references/safety.md\` and \`gridpane-core/references/paths.md\` before any call."
mkdir -p "$FIXTURE/skills/gridpane-api/references"
printf '# endpoints\n\nEvidence in gridpane-core/references/sources.md.\n' \
    >"$FIXTURE/skills/gridpane-api/references/endpoints.md"

# Dev noise and the moved template must never reach an archive.
mkdir -p "$FIXTURE/skills/gridpane-api/tests" "$FIXTURE/skills/gridpane-api/evals"
printf '#!/usr/bin/env bash\n' >"$FIXTURE/skills/gridpane-api/tests/test_thing.sh"
printf 'old\n' >"$FIXTURE/skills/gridpane-api/references/old.md.bak"
printf 'junk\n' >"$FIXTURE/skills/gridpane-api/.DS_Store"
printf 'case: []\n' >"$FIXTURE/skills/gridpane-api/evals/case.yaml"
skill_md "$FIXTURE/templates/skill/SKILL.md" gridpane-example "Template skeleton."

tree_hash() { # <dir>
    ( cd "$1" && find skills -type f -print0 | sort -z | xargs -0 sha256sum ) | sha256sum | awk '{print $1}'
}

before_hash="$(tree_hash "$FIXTURE")"

# --- 1. build and layout ---------------------------------------------------

"$FIXTURE/scripts/build-zips.sh" --out "$WORK/out" >"$WORK/build.log" 2>&1 \
    || { cat "$WORK/build.log" >&2; fail "fixture build failed"; }
mapfile -t zips < <(find "$WORK/out" -maxdepth 1 -name '*.zip' -printf '%f\n' | sort)
[[ "${#zips[@]}" -eq 3 ]] || fail "expected 3 fixture archives, got ${#zips[@]}: ${zips[*]}"
ok "fixture builds one archive per skill plus the all-in-one"

python3 - "$WORK/out" <<'PY' || exit 1
import sys
import zipfile
from pathlib import Path

out = Path(sys.argv[1])
api = out / "gridpane-api.zip"
with zipfile.ZipFile(api) as zf:
    names = [n for n in zf.namelist() if not n.endswith("/")]
    roots = {n.split("/", 1)[0] for n in names}
    assert roots == {"gridpane-api"}, roots
    assert "gridpane-api/SKILL.md" in names
    assert not any(n.endswith(".tmp") for n in names)

    skill = zf.read("gridpane-api/SKILL.md").decode()
    assert "references/safety.md" in skill
    assert "references/paths.md" in skill
    assert "gridpane-core/references/" not in skill

    for mandatory in ("safety.md", "paths.md", "gp-conventions.md"):
        assert f"gridpane-api/references/{mandatory}" in names, mandatory

    vendored = "gridpane-api/references/vendor/gridpane-core/references/sources.md"
    assert vendored in names, names
    endpoints = zf.read("gridpane-api/references/endpoints.md").decode()
    assert "references/vendor/gridpane-core/references/sources.md" in endpoints
    assert "gridpane-core/references/sources.md" not in endpoints.replace(
        "references/vendor/gridpane-core/references/sources.md", ""
    )

    for bad in ("tests/", "evals/", ".DS_Store", ".bak", "templates/", "gridpane-example"):
        assert not any(bad in n for n in names), (bad, names)

with zipfile.ZipFile(out / "gridpane-core.zip") as zf:
    names = [n for n in zf.namelist() if not n.endswith("/")]
    vendored = "gridpane-core/references/vendor/gridpane-api/references/endpoints.md"
    assert vendored in names, names
    sources = zf.read("gridpane-core/references/sources.md").decode()
    assert "references/vendor/gridpane-api/references/endpoints.md" in sources
    assert not any("templates/" in n or "gridpane-example" in n for n in names)

with zipfile.ZipFile(out / "gridpane-skills-all.zip") as zf:
    roots = {n.split("/", 1)[0] for n in zf.namelist() if not n.endswith("/")}
    assert roots == {"gridpane-api", "gridpane-core"}, roots
    assert not any("templates/" in n for n in zf.namelist())
PY
ok "archive layout, mandatory core copies and rewritten references are correct"

# --- 2. no external references remain in a standalone archive --------------

python3 - "$WORK/out" <<'PY' || exit 1
import re
import sys
import zipfile
from pathlib import Path

pattern = re.compile(r"(?<!vendor/)(?:\.\./|skills/)?(gridpane-[a-z0-9-]+)/references/[A-Za-z0-9._/-]+")
out = Path(sys.argv[1])
remaining = []
for archive in sorted(out.glob("*.zip")):
    if archive.name == "gridpane-skills-all.zip":
        continue
    with zipfile.ZipFile(archive) as zf:
        for name in zf.namelist():
            if not name.endswith(".md"):
                continue
            for match in pattern.finditer(zf.read(name).decode()):
                remaining.append((archive.name, name, match.group(0)))
assert not remaining, remaining[:5]
PY
ok "standalone archives contain no unresolved cross-skill reference"

# --- 3. the source tree is untouched ---------------------------------------

after_hash="$(tree_hash "$FIXTURE")"
[[ "$before_hash" == "$after_hash" ]] || fail "build modified the source skill tree"
ok "build leaves the source tree untouched"

# --- 4. repeatable output --------------------------------------------------

"$FIXTURE/scripts/build-zips.sh" --out "$WORK/out2" >/dev/null 2>&1 || fail "second build failed"
for name in "${zips[@]}"; do
    a="$(sha256sum "$WORK/out/$name" | awk '{print $1}')"
    b="$(sha256sum "$WORK/out2/$name" | awk '{print $1}')"
    [[ "$a" == "$b" ]] || fail "archive is not deterministic: $name"
done
ok "archives are byte-for-byte repeatable"

# --- 5. name/folder mismatch fails before writing --------------------------

cp -R "$FIXTURE" "$WORK/mismatch"
mv "$WORK/mismatch/skills/gridpane-api" "$WORK/mismatch/skills/gridpane-api-wrong"
if "$WORK/mismatch/scripts/build-zips.sh" --out "$WORK/mismatch-out" >"$WORK/mismatch.log" 2>&1; then
    fail "name/folder mismatch was accepted"
fi
grep -q 'does not match folder' "$WORK/mismatch.log" || fail "missing name mismatch message"
if find "$WORK/mismatch-out" -maxdepth 1 -name '*.zip' -print -quit | grep -q .; then
    fail "mismatch build left a partial archive"
fi
ok "name/folder mismatch fails with no partial archive"

# --- 6. byte limit ---------------------------------------------------------

if CLAUDE_SKILL_ZIP_MAX_BYTES=1 "$FIXTURE/scripts/build-zips.sh" --out "$WORK/limit-out" >"$WORK/limit.log" 2>&1; then
    fail "a one-byte limit was accepted"
fi
grep -q 'CLAUDE_SKILL_ZIP_MAX_BYTES' "$WORK/limit.log" || fail "missing limit message"
ok "an oversized archive fails the build"

# --- 7. the real repository builds the full set ----------------------------

"$REPO_ROOT/scripts/build-zips.sh" --out "$WORK/real" >"$WORK/real.log" 2>&1 \
    || { cat "$WORK/real.log" >&2; fail "repository build failed"; }
python3 - "$WORK/real" "$REPO_ROOT" <<'PY' || exit 1
import sys
import zipfile
from pathlib import Path

out = Path(sys.argv[1])
root = Path(sys.argv[2])
expected = sorted(p.parent.name for p in (root / "skills").glob("gridpane-*/SKILL.md"))
archives = sorted(p.stem for p in out.glob("*.zip"))
assert archives == sorted(expected + ["gridpane-skills-all"]), archives
for name in expected:
    with zipfile.ZipFile(out / f"{name}.zip") as zf:
        names = [n for n in zf.namelist() if not n.endswith("/")]
        roots = {n.split("/", 1)[0] for n in names}
        assert roots == {name}, (name, roots)
        assert f"{name}/SKILL.md" in names
        assert not any("templates/" in n or "gridpane-example" in n for n in names)
with zipfile.ZipFile(out / "gridpane-skills-all.zip") as zf:
    roots = {n.split("/", 1)[0] for n in zf.namelist() if not n.endswith("/")}
    assert roots == set(expected), roots
PY
ok "repository builds one archive per skill plus the all-in-one"

printf 'All build-zips tests passed.\n'
