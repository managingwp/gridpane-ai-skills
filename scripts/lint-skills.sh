#!/usr/bin/env bash
#
# lint-skills.sh - repository checks for the GridPane Agent Skills.
#
# Checks:
#   1. SKILL.md frontmatter: name matches the folder, description <= 1024 chars.
#   2. Every bash/sh code fence carries a [READ]/[WRITE]/[DESTRUCTIVE] label.
#   3. Relative markdown links resolve to a file in the repo.
#   4. No obvious secrets (private keys, bearer tokens, AWS keys, assignments).
#   5. No real-looking IPv4 addresses (RFC 5737 / loopback only).
#   6. No real-looking domains outside an allowlist.
#
# Exits non-zero if any check fails.
#
# Usage: lint-skills.sh [skills-dir]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="${1:-$REPO_ROOT/skills}"

errors=0
error() { printf 'LINT: %s\n' "$1" >&2; errors=$(( errors + 1 )); }

# Domains that are allowed to appear (vendors, docs, examples).
DOMAIN_ALLOWLIST='example\.com|example\.org|example\.net|gridpane\.com|cloudflare\.com|google\.com|googleapis\.com|wordpress\.org|nginx\.org|postman\.com|github\.com|redis\.io|fail2ban\.org|askubuntu\.com|loggly\.com|perishablepress\.com|context7\.com|glama\.ai|managingwp\.io|keepachangelog\.com|semver\.org|editorconfig\.org|documenter\.getpostman\.com|documenter\.gw\.postman\.com|my\.gridpane\.com|status\.gridpane\.com|roadmap\.gridpane\.com|core-api\.upvotyfeedback\.com|docs\.litespeedtech\.com'

# ---------------------------------------------------------------------------
# 1-3. Per-skill checks
# ---------------------------------------------------------------------------

while IFS= read -r skill_md; do
    skill_dir="$(dirname "$skill_md")"
    folder="$(basename "$skill_dir")"

    [[ "$folder" == _* ]] && continue   # skip _template

    # Frontmatter block: lines between the first two "---" lines.
    fm="$(awk 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {exit} f {print}' "$skill_md")"
    if [[ -z "$fm" ]]; then
        error "$skill_md: missing or empty frontmatter"
        continue
    fi

    name="$(printf '%s\n' "$fm" | awk -F':[[:space:]]*' '/^name:/{print $2; exit}' | tr -d ' "')"
    if [[ "$name" != "$folder" ]]; then
        error "$skill_md: frontmatter name '$name' does not match folder '$folder'"
    fi

    desc_len="$(printf '%s\n' "$fm" | awk '/^description:/{f=1} f{print}' | wc -c | tr -d ' ')"
    if [[ "$desc_len" -gt 1024 ]]; then
        error "$skill_md: description is $desc_len chars (> 1024)"
    fi

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

if [[ "$errors" -gt 0 ]]; then
    printf '\nlint-skills: %d problem(s) found\n' "$errors" >&2
    exit 1
fi

printf 'lint-skills: all checks passed\n'
