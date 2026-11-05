#!/usr/bin/env bash
#
# build-zips.sh - build upload-ready skill archives for claude.ai.
#
# For every skills/gridpane-* skill this writes dist/<skill-name>.zip with the
# skill folder at the archive root, plus dist/gridpane-skills-all.zip with every
# skill side by side. A standalone archive carries local copies of every
# cross-skill reference it cites, and the staged copies are rewritten to point
# at those local files. The source tree is never modified.
#
# Python 3 (standard library only) builds the archives and rewrites the staged
# copies; the shell entry point owns argument handling and the byte limit.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$REPO_ROOT/dist"

# claude.ai does not publish the custom-skill ZIP byte limit in its skill
# documentation. 10 MiB is a conservative provisional default, not a
# documented figure. TODO: replace it once Anthropic publishes the limit.
DEFAULT_MAX_BYTES=10485760

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [--out DIR]

Build upload-ready archives for every skills/gridpane-* skill:

  DIR/<skill-name>.zip          one skill, folder at the archive root, with
                                local copies of every cross-skill reference
  DIR/gridpane-skills-all.zip   every skill side by side

The source tree is never modified. Archives are deterministic: sorted entries,
fixed timestamps and permissions.

Options:
  --out DIR      Output directory (default: ${REPO_ROOT}/dist).
  -h, --help     Show this help.

Environment:
  CLAUDE_SKILL_ZIP_MAX_BYTES   Maximum size of one archive, in bytes
                               (default: ${DEFAULT_MAX_BYTES}, a provisional
                               value; claude.ai does not document a limit).
                               The build fails when an archive exceeds it.

Requires: bash 4+, Python 3 (standard library only).
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) OUT_DIR="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'error: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ -z "$OUT_DIR" ]]; then
    printf 'error: --out needs a directory\n' >&2
    exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
    printf 'error: python3 is required to build the archives\n' >&2
    exit 1
fi

MAX_BYTES="${CLAUDE_SKILL_ZIP_MAX_BYTES:-$DEFAULT_MAX_BYTES}"
case "$MAX_BYTES" in
    ''|*[!0-9]*)
        printf 'error: CLAUDE_SKILL_ZIP_MAX_BYTES must be a positive integer\n' >&2
        exit 2
        ;;
esac
if [[ "$MAX_BYTES" -le 0 ]]; then
    printf 'error: CLAUDE_SKILL_ZIP_MAX_BYTES must be greater than zero\n' >&2
    exit 2
fi

mkdir -p "$OUT_DIR"
# Replace the previous build, not the rest of the directory.
find "$OUT_DIR" -maxdepth 1 -type f -name '*.zip' -delete

STAGING="$(mktemp -d)"
cleanup() { rm -rf "$STAGING"; }
trap cleanup EXIT

python3 - "$REPO_ROOT" "$OUT_DIR" "$MAX_BYTES" "$STAGING" <<'PY'
"""Stage standalone skill copies and build deterministic ZIP archives."""

from __future__ import annotations

import os
import re
import shutil
import stat
import sys
import zipfile
from pathlib import Path

repo = Path(sys.argv[1]).resolve()
out_dir = Path(sys.argv[2]).resolve()
max_bytes = int(sys.argv[3])
staging_root = Path(sys.argv[4]).resolve()

skills_root = repo / "skills"
core_name = "gridpane-core"
mandatory_core = ("safety.md", "paths.md", "gp-conventions.md")

NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
# A sibling skill's reference path, with an optional ../ or skills/ prefix.
REF_RE = re.compile(
    r"(?<![A-Za-z0-9_-])"
    r"(?:(?:\.\./)+|skills/)?"
    r"(gridpane-[a-z0-9-]+)/references/"
    r"([A-Za-z0-9._/-]+?\.(?:md|json|sh|txt|py|yaml|yml))"
)

SKIP_DIRS = {"tests", "test", "evals", "__pycache__", ".git", "node_modules"}
SKIP_NAMES = {".DS_Store", ".gitignore"}
SKIP_SUFFIXES = (".bak", ".orig", ".swp", "~")


def fail(message: str) -> None:
    print(f"build-zips: {message}", file=sys.stderr)
    raise SystemExit(1)


def excluded(rel: Path) -> bool:
    if any(part in SKIP_DIRS for part in rel.parts[:-1]):
        return True
    name = rel.name
    if name in SKIP_NAMES:
        return True
    if name.startswith(".DS_Store"):
        return True
    if name.endswith(SKIP_SUFFIXES) or ".bak-" in name:
        return True
    return False


def frontmatter_name(skill_md: Path) -> str:
    text = skill_md.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        fail(f"{skill_md}: missing frontmatter")
    value = ""
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if line.startswith("name:"):
            value = line.split(":", 1)[1].strip().strip('"').strip("'")
    return value


def copy_skill(src: Path, dest: Path) -> None:
    for path in sorted(src.rglob("*")):
        rel = path.relative_to(src)
        if excluded(rel):
            continue
        target = dest / rel
        if path.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)


def zip_tree(archive_path: Path, entries: list[tuple[Path, str]]) -> None:
    """Write deterministic archives; entries are (source file, arcname)."""
    tmp = archive_path.with_suffix(".zip.tmp")
    with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for source, arcname in sorted(entries, key=lambda item: item[1]):
            info = zipfile.ZipInfo(arcname, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.compress_type = zipfile.ZIP_DEFLATED
            mode = 0o755 if source.stat().st_mode & 0o111 else 0o644
            info.external_attr = (stat.S_IFREG | mode) << 16
            zf.writestr(info, source.read_bytes())
    os.replace(tmp, archive_path)


def tree_entries(root: Path, prefix: str) -> list[tuple[Path, str]]:
    entries = []
    for path in sorted(root.rglob("*")):
        rel = path.relative_to(root)
        if excluded(rel):
            continue
        if path.is_file():
            entries.append((path, f"{prefix}{rel.as_posix()}"))
    return entries


# Discover and validate every skill before writing any archive.
skills = sorted(
    path
    for path in skills_root.iterdir()
    if path.is_dir() and path.name.startswith("gridpane-") and (path / "SKILL.md").is_file()
)
if not skills:
    fail(f"no skills/gridpane-*/SKILL.md found under {skills_root}")

declared: dict[str, Path] = {}
for skill in skills:
    name = frontmatter_name(skill / "SKILL.md")
    if not NAME_RE.match(name):
        fail(f"{skill}/SKILL.md: name '{name}' must use lowercase letters, digits and single hyphens")
    if name != skill.name:
        fail(f"{skill}/SKILL.md: frontmatter name '{name}' does not match folder '{skill.name}'")
    if name in declared:
        fail(f"duplicate skill name '{name}'")
    declared[name] = skill
if core_name not in declared:
    fail(f"skills/{core_name} is required to resolve core references")

built: list[Path] = []


def add_mandatory_core(stage: Path) -> dict[str, str]:
    """Copy the mandatory core references under collision-safe local names."""
    mapping: dict[str, str] = {}
    references = stage / "references"
    references.mkdir(parents=True, exist_ok=True)
    for filename in mandatory_core:
        source = skills_root / core_name / "references" / filename
        if not source.is_file():
            fail(f"missing required core reference: {source}")
        local_rel = f"references/{filename}"
        if (stage / local_rel).exists():
            local_rel = f"references/{core_name}-{filename}"
        target = stage / local_rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        mapping[f"{core_name}/references/{filename}"] = local_rel
    return mapping


def bundle_references(stage: Path, mapping: dict[str, str], host_name: str) -> None:
    """Vendor every external reference and rewrite staged copies."""
    used_local = {value for value in mapping.values()}
    queue: list[Path] = [p for p in stage.rglob("*.md") if p.is_file()]
    processed: set[Path] = set()

    def ensure_target(target: str) -> str:
        if target in mapping:
            return mapping[target]
        skill, rel = target.split("/references/", 1)
        # A reference back into the host skill is already in the package.
        if skill == host_name and (stage / "references" / rel).is_file():
            local_rel = f"references/{rel}"
            mapping[target] = local_rel
            return local_rel
        source = skills_root / skill / "references" / rel
        if not source.is_file():
            fail(f"referenced file does not exist: skills/{skill}/references/{rel}")
        local_rel = f"references/vendor/{skill}/references/{rel}"
        if local_rel in used_local:
            fail(f"reference collision at {local_rel}")
        used_local.add(local_rel)
        destination = stage / local_rel
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        mapping[target] = local_rel
        queue.append(destination)
        return local_rel

    while queue:
        md = queue.pop(0)
        md = md.resolve()
        if md in processed or not md.is_file():
            continue
        processed.add(md)
        text = md.read_text(encoding="utf-8")
        changed = False

        def replace(match: re.Match[str]) -> str:
            nonlocal changed
            target = f"{match.group(1)}/references/{match.group(2)}"
            local_rel = ensure_target(target)
            changed = True
            return local_rel

        updated = REF_RE.sub(replace, text)
        if changed and updated != text:
            md.write_text(updated, encoding="utf-8")


for skill in skills:
    stage = staging_root / skill.name
    copy_skill(skill, stage)
    mapping: dict[str, str] = {}
    if skill.name != core_name:
        mapping = add_mandatory_core(stage)
    bundle_references(stage, mapping, skill.name)
    archive = out_dir / f"{skill.name}.zip"
    zip_tree(archive, tree_entries(stage, f"{skill.name}/"))
    built.append(archive)

all_entries: list[tuple[Path, str]] = []
for skill in skills:
    all_entries.extend(tree_entries(skill, f"{skill.name}/"))
all_archive = out_dir / "gridpane-skills-all.zip"
zip_tree(all_archive, all_entries)
built.append(all_archive)

too_large = []
for archive in built:
    size = archive.stat().st_size
    print(f"{archive.name} {size} bytes")
    if size > max_bytes:
        too_large.append((archive.name, size))

if too_large:
    for name, size in too_large:
        print(
            f"build-zips: {name} is {size} bytes, over the {max_bytes}-byte limit",
            file=sys.stderr,
        )
    fail("one or more archives exceed CLAUDE_SKILL_ZIP_MAX_BYTES")

print(f"build-zips: built {len(built)} archives in {out_dir}")
PY
