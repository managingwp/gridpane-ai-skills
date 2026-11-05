#!/usr/bin/env bash
#
# lint-skills.sh - repository checks for the GridPane Agent Skills.
#
# Checks:
#   1. SKILL.md frontmatter: name grammar and folder match, description <= 200
#      characters (the claude.ai limit).
#   2. Every bash/sh code fence carries a [READ]/[WRITE]/[DESTRUCTIVE] label.
#   3. Relative markdown links resolve to a file in the repo, and no package
#      file points at a workstation absolute path or an absolute markdown link.
#   4. No obvious secrets (private keys, bearer tokens, AWS keys, assignments).
#   5. No real-looking IPv4 addresses (RFC 5737 / loopback only).
#   6. No real-looking domains outside an allowlist.
#
# Exits non-zero if any check fails.
#
# Usage: lint-skills.sh [skills-dir]   (or --help)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
usage() {
    cat <<EOF
Usage: lint-skills.sh [skills-dir]

Repository checks for the GridPane Agent Skills: SKILL.md frontmatter, command
labels, relative links, secrets, IPs and domains. Run from the repo root; exits
non-zero when a check fails.

Options:
  [skills-dir]   Directory to lint (default: <repo>/skills)
  -h, --help     Show this help and exit
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "")        SKILLS_DIR="$REPO_ROOT/skills" ;;
    *)         SKILLS_DIR="$1" ;;
esac

errors=0
error() { printf 'LINT: %s\n' "$1" >&2; errors=$(( errors + 1 )); }

# Domains that are allowed to appear (vendors, docs, examples).
DOMAIN_ALLOWLIST='example\.com|example\.org|example\.net|gridpane\.com|cloudflare\.com|google\.com|googleapis\.com|wordpress\.org|nginx\.org|postman\.com|github\.com|redis\.io|fail2ban\.org|askubuntu\.com|loggly\.com|perishablepress\.com|context7\.com|glama\.ai|managingwp\.io|keepachangelog\.com|semver\.org|editorconfig\.org|documenter\.getpostman\.com|documenter\.gw\.postman\.com|my\.gridpane\.com|status\.gridpane\.com|roadmap\.gridpane\.com|core-api\.upvotyfeedback\.com|docs\.litespeedtech\.com|manpages\.ubuntu\.com'

# ---------------------------------------------------------------------------
# 1-3. Per-skill checks
# ---------------------------------------------------------------------------

# Read one frontmatter key, unfolding a YAML block scalar into one line.
# Usage: fm_value <SKILL.md> <key>
fm_value() {
    awk -v key="$2" '
        NR == 1 && $0 == "---" { inf = 1; next }
        inf && $0 == "---" { exit }
        !inf { next }
        index($0, key ":") == 1 {
            value = substr($0, length(key) + 2)
            sub(/^[ \t]+/, "", value)
            sub(/[ \t]+$/, "", value)
            if (value != "" && value !~ /^[>|][-+]?$/) { print value; exit }
            literal = (value ~ /^\|/)
            while ((getline line) > 0) {
                if (line ~ /^[^ \t]/) break
                sub(/^[ \t]+/, "", line)
                sub(/[ \t]+$/, "", line)
                if (line == "") continue
                if (out == "") out = line
                else out = out (literal ? "\n" : " ") line
            }
            print out
            exit
        }
    ' "$1"
}

while IFS= read -r skill_md; do
    skill_dir="$(dirname "$skill_md")"
    folder="$(basename "$skill_dir")"

    # Frontmatter block: lines between the first two "---" lines.
    fm="$(awk 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {exit} f {print}' "$skill_md")"
    if [[ -z "$fm" ]]; then
        error "$skill_md: missing or empty frontmatter"
        continue
    fi

    name="$(fm_value "$skill_md" name)"
    if [[ -z "$name" ]]; then
        error "$skill_md: missing required frontmatter field 'name'"
    else
        if ! printf '%s' "$name" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then
            error "$skill_md: name '$name' must use lowercase letters, digits and single hyphens"
        fi
        if [[ "$name" != "$folder" ]]; then
            error "$skill_md: frontmatter name '$name' does not match folder '$folder'"
        fi
    fi

    desc="$(fm_value "$skill_md" description)"
    if [[ -z "$desc" ]]; then
        error "$skill_md: missing required frontmatter field 'description'"
    else
        # claude.ai rejects a description over 200 characters.
        desc_len="$(printf '%s' "$desc" | awk '{ print length($0) }')"
        if [[ "$desc_len" -gt 200 ]]; then
            error "$skill_md: description is $desc_len chars (> 200 claude.ai limit)"
        fi
    fi

    # Package paths must stay inside the uploaded skill. Documentation of real
    # GridPane server paths (/etc, /var/www, /root, /usr/local/bin) is expected
    # and allowed; a link or build path rooted anywhere else is not.
    while IFS= read -r md; do
        while IFS= read -r hit; do
            [[ -z "$hit" ]] && continue
            error "$md:$hit: absolute package link; use a relative path"
        done < <(grep -nE '\]\(/[^)]*\)' "$md" 2>/dev/null || true)
        while IFS= read -r hit; do
            [[ -z "$hit" ]] && continue
            error "$md:$hit: workstation absolute path; uploaded packages must be self-contained"
        done < <(grep -nE '/home/|/Users/|(^|[^[:alnum:]])[A-Za-z]:[\\/]' "$md" 2>/dev/null || true)
    done < <(find "$skill_dir" -type f -name '*.md' | sort)

    # Every bash/sh fence must contain a label.
    bad_lines="$(awk '
        /^```(bash|sh)[[:space:]]*$/ { inb=1; buf=""; next }
        inb && /^```/ {
            if (buf !~ /\[(READ|WRITE|DESTRUCTIVE)\]/) { printf "%d ", NR }
            inb=0; next
        }
        inb { buf=buf $0 "\n" }
    ' "$skill_md")"
    if [[ -n "$bad_lines" ]]; then
        error "$skill_md: unlabelled bash/sh code block(s) near line(s): ${bad_lines% }"
    fi

    # Relative links resolve.
    while IFS= read -r link; do
        [[ -z "$link" ]] && continue
        case "$link" in
            http*|mailto:*|\#*|*\{*|*\<*) continue ;;
        esac
        target="${link%%#*}"
        [[ -z "$target" ]] && continue
        if [[ ! -e "$skill_dir/$target" ]]; then
            error "$skill_md: relative link does not resolve: $link"
        fi
    done < <(grep -oE '\]\([^)]+\)' "$skill_md" | sed -E 's/^\]\(//; s/\)$//')

done < <(find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -name SKILL.md | sort)

# ---------------------------------------------------------------------------
# 4. Secrets
# ---------------------------------------------------------------------------

secret_globs=(
    'BEGIN [A-Z ]*PRIVATE KEY'
    'AKIA[0-9A-Z]{16}'
    'Bearer [A-Za-z0-9_-]{24,}'
    'xox[baprs]-[A-Za-z0-9-]+'
)
for pat in "${secret_globs[@]}"; do
    while IFS= read -r hit; do
        [[ -z "$hit" ]] && continue
        error "possible secret ($pat): $hit"
    done < <(grep -rInE --exclude=docs-manifest.json --exclude=changelog-manifest.json "$pat" "$SKILLS_DIR" 2>/dev/null | grep -v 'BEGIN \[A-Z \]\*PRIVATE KEY' || true)
done

# Plaintext credential assignments (password=/secret=/token= with a long value).
while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    error "possible credential assignment: $hit"
done < <(grep -rInE --exclude=docs-manifest.json --exclude=changelog-manifest.json '(password|passwd|secret|token|api[_-]?key)["'"'"']?[:=][[:space:]]*["'"'"']?[A-Za-z0-9]{16,}' "$SKILLS_DIR" 2>/dev/null || true)

# ---------------------------------------------------------------------------
# 5. Real-looking IPv4 addresses
# ---------------------------------------------------------------------------

while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    ip="${hit##*:}"
    case "$ip" in
        203.0.113.*|198.51.100.*|192.0.2.*|127.0.0.1|0.0.0.0) ;;   # allowed
        *) error "non-documentation IPv4 address: $hit" ;;
    esac
done < <(grep -rIohE --exclude=docs-manifest.json --exclude=changelog-manifest.json '([0-9]{1,3}\.){3}[0-9]{1,3}' "$SKILLS_DIR" 2>/dev/null | sort -u | sed 's/^/ip:/' || true)

# ---------------------------------------------------------------------------
# 6. Real-looking domains
# ---------------------------------------------------------------------------

while IFS= read -r dom; do
    [[ -z "$dom" ]] && continue
    if ! printf '%s' "$dom" | grep -qE "^(${DOMAIN_ALLOWLIST})$"; then
        error "non-allowlisted domain: $dom"
    fi
done < <(grep -rIohE --exclude=docs-manifest.json --exclude=changelog-manifest.json '[A-Za-z0-9][A-Za-z0-9.-]*\.(com|net|org|io|co|dev|cloud|ai)\b' "$SKILLS_DIR" 2>/dev/null \
            | grep -vE '\.(com|net|org|io|co|dev|cloud|ai)\.' | sort -u || true)

# ---------------------------------------------------------------------------
# 7. Claude package versions agree with VERSION
# ---------------------------------------------------------------------------

if [[ "$SKILLS_DIR" == "$REPO_ROOT/skills" && -d "$REPO_ROOT/.claude-plugin" ]]; then
    version_report="$(python3 - "$REPO_ROOT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
version_file = (root / "VERSION").read_text().strip()
plugin = json.loads((root / ".claude-plugin/plugin.json").read_text())
marketplace = json.loads((root / ".claude-plugin/marketplace.json").read_text())
values = {
    "VERSION": version_file,
    "plugin.json": plugin.get("version"),
    "marketplace.json": marketplace.get("version"),
}
for entry in marketplace.get("plugins", []):
    values[f"marketplace.json[{entry.get('name')}]"] = entry.get("version")
bad = {name: value for name, value in values.items() if value != version_file}
for name, value in bad.items():
    print(f"{name} is {value!r} but VERSION is {version_file!r}")
raise SystemExit(1 if bad else 0)
PY
)" || error "Claude package versions are out of sync: ${version_report//$'\n'/; } (run scripts/git-squash-release.sh to assign a release version)"
fi

# ---------------------------------------------------------------------------

if [[ "$errors" -gt 0 ]]; then
    printf '\nlint-skills: %d problem(s) found\n' "$errors" >&2
    exit 1
fi

printf 'lint-skills: all checks passed\n'
