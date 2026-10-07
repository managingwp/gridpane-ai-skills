#!/usr/bin/env bash
#
# install.sh - copy or symlink the Agent Skills into a target skills directory.
#
# Always installs gridpane-core (the other skills depend on it). Idempotent: a
# skill already present in the target is replaced.
#
# Usage: install.sh --target DIR [--link] [--skills a,b,c] [--help]

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$REPO_ROOT/skills"

TARGET=""
LINK=0
SKILLS=""

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} --target DIR [options]

Copy (or symlink) the GridPane Agent Skills into DIR. gridpane-core is always
included.

Options:
  --target DIR        Destination skills directory (required).
  --link              Symlink each skill instead of copying.
  --skills a,b,c      Install only these skills (plus gridpane-core).
  -h, --help          Show this help.

Examples:
  ${SCRIPT_NAME} --target ~/.claude/skills
  ${SCRIPT_NAME} --target .agents/skills --link
  ${SCRIPT_NAME} --target .claude/skills --skills gridpane-incident-triage
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="${2:-}"; shift 2 ;;
        --link) LINK=1; shift ;;
        --skills) SKILLS="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'error: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ -z "$TARGET" ]]; then
    printf 'error: --target is required\n' >&2
    usage >&2
    exit 2
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
    printf 'error: source skills dir not found: %s\n' "$SOURCE_DIR" >&2
    exit 1
fi

mkdir -p "$TARGET"

# Determine the skill list: explicit --skills plus gridpane-core, or all skills.
selected=()
if [[ -n "$SKILLS" ]]; then
    IFS=',' read -r -a requested <<<"$SKILLS"
    selected+=("${requested[@]}")
else
    while IFS= read -r name; do
        selected+=("$name")
    done < <(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
fi

# Always include core, and never install the template.
has_core=0
for s in "${selected[@]}"; do
    [[ "$s" == "gridpane-core" ]] && has_core=1
done
[[ "$has_core" -eq 1 ]] || selected=("gridpane-core" "${selected[@]}")

install_one() {
    local name="$1"
    local src="$SOURCE_DIR/$name"
    local dest="$TARGET/$name"

    if [[ ! -d "$src" ]]; then
        printf 'error: skill not found: %s\n' "$name" >&2
        return 1
    fi

    rm -rf "$dest"
    if [[ "$LINK" -eq 1 ]]; then
        ln -s "$src" "$dest"
        printf 'linked %s -> %s\n' "$name" "$dest"
    else
        cp -R "$src" "$dest"
        printf 'copied %s -> %s\n' "$name" "$dest"
    fi
}

for name in "${selected[@]}"; do
    [[ -z "$name" ]] && continue
    [[ "$name" == _* ]] && continue
    if [[ "$name" == "gridpane-core" ]]; then
        continue
    fi
    install_one "$name"
done
install_one "gridpane-core"

printf '\nInstalled %d skill(s) into %s\n' "$(( ${#selected[@]} ))" "$TARGET"
