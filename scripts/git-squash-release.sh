#!/usr/bin/env bash
# =================================================================================================
# scripts/git-squash-release.sh -- Squash commits since the last tag into a release commit
# -------------------------------------------------------------------------------------------------
# Standalone bash 4+ port of zshbop's `git-squash-release` shell function
# (zshbop/cmds/cmds-git.zsh). Self-contained: the zshbop framework helpers
# (_loading, _loading2, _success, _warning, _error, _debug) are replaced by
# script-local _gsr_* helpers.
#
# Vendored 2026-11-05 from the canonical plan-generation-skill copy:
#   <skill-dir>/scripts/git-squash-release.sh
# Local additions: the .claude-plugin manifests are writable version sources,
# and a release promotes CHANGELOG.md's "## Unreleased" section to the release
# version. See tests/scripts/test_git_squash_release.sh for the local cases.
# =================================================================================================
set -uo pipefail
shopt -s nullglob

# -- Colors (disabled when stdout is not a TTY; force with GSR_COLOR=1).
if [[ -t 1 || "${GSR_COLOR:-0}" == "1" ]]; then
    C_RESET=$'\033[0m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_CYAN=$'\033[36m'
    C_BLACK=$'\033[30m'
    C_BG_YELLOW=$'\033[43m'
    C_BG_GREY=$'\033[47m'
else
    C_RESET="" C_RED="" C_GREEN="" C_YELLOW="" C_CYAN="" C_BLACK="" C_BG_YELLOW="" C_BG_GREY=""
fi

# ------------------------------------------------------------
# -- Output helpers (replace zshbop's _success/_warning/_error/_debug/_loading*)
# ------------------------------------------------------------
_gsr_success () { printf '%s * %s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
_gsr_warning () { printf '%s * %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
_gsr_error   () { printf '%s * %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; }
_gsr_debug   () { [[ "${ZSH_DEBUG:-0}" == "1" ]] && printf '%s** [DEBUG]: %s%s\n' "$C_CYAN" "$*" "$C_RESET"; return 0; }
_gsr_loading () { printf '%s%s * %s%s\n' "$C_BG_YELLOW" "$C_BLACK" "$*" "$C_RESET"; }
_gsr_loading2() { printf '%s%s ** %s%s\n' "$C_BG_GREY" "$C_BLACK" "$*" "$C_RESET"; }

_gsr_have () { command -v "$1" >/dev/null 2>&1; }

# -- _gsr_latest_tag : echo the latest reachable tag or nothing
_gsr_latest_tag () { git describe --tags --abbrev=0 2>/dev/null || true; }

# ------------------------------------------------------------
# -- Usage
# ------------------------------------------------------------
usage () {
    cat <<'EOF'
Usage: git-squash-release [-h|--help] [-d|--detect] [--status] [-f|--force] [-s|--squash] [-i|--init] [-r|--repo <path>]

Squash all commits since the last tag into a single release commit.

Options:
  -d, --detect    Run preflight detections only (no git changes)
      --status    Print the compact Version & Release Gate line and exit
                  (read-only: no prompts, no locks, no git changes)
  -f, --force     Bypass failed preflight checks and proceed anyway (never
                  bypasses a PGF plan lock or release marker)
      --ignore-pgf-lock
                  Proceed while a PGF execution lock is held (explicit override;
                  only with the lock owner's approval)
      --allow-version-drift
                  Release anyway when a writable version source differs from the
                  last tag. The release is still calculated from the last tag and
                  rewrites every writable source. Malformed values never pass.
  -s, --squash    Squash commits since last tag without tagging or version bump
                  (uses first line + commit ID of each squashed commit)
  -i, --init      Squash entire commit history from the first commit into one commit
                  (no tag or version required)
  -r, --repo      Run against the repository at <path>
  -y, --yes       Assume yes for confirmation prompts (non-interactive); does not
                  push unless --push is also given
      --bump      Bump type: 'minor' or 'major' (skips the interactive prompt)
  -p, --push      Force-push branch and tags at the end without asking
      --no-push   Never push, regardless of prompts
      --main BRANCH            Main branch to check divergence against (auto-detected
                               from origin/HEAD, then main, then master)
      --skip-divergence-check  Skip the main-branch divergence safety check

Version is detected from package.json, WordPress plugin/theme headers, or a
VERSION file (package.json preferred). WordPress plugin/theme detection is
scoped to the repo-named folder (./<repo-name>/), falling back to the repo
root (./style.css for themes, ./<repo-name>.php for plugins). The git tag is
the source of truth for the release version; if the detected version differs
from the last tag you are prompted to tag using the detected version instead.

Claude plugin and marketplace manifests (.claude-plugin/plugin.json and
.claude-plugin/marketplace.json) are writable version sources when present, and
a release promotes CHANGELOG.md's "## Unreleased" section to "## v<version>".
Both need python3.

Default mode prompts for minor or major version bump, writes the version as a
chore: bump version commit, squashes commits since the last tag, tags the
release, and optionally pushes.
EOF
}

# ==============================================
# -- _gsr_detect_wp_plugin
# -- Detect the WordPress plugin file for this repo, scoped to the repo-named folder
# ==============================================
_gsr_detect_wp_plugin () {
    local repo_basename plugin_file
    repo_basename="$(basename "$PWD")"

    # Search only the repo-named folder (not the whole repo) for a Plugin Name header.
    plugin_file="$(grep -RIl -i --include='*.php' '^[[:space:]]*\*\{0,1\}[[:space:]]*Plugin Name[[:space:]]*:' "./${repo_basename}" 2>/dev/null | head -n 1)"

    # Fallback: <repo-basename>.php in the repository root.
    if [[ -z $plugin_file && -f "./${repo_basename}.php" ]]; then
        plugin_file="./${repo_basename}.php"
    fi

    printf '%s\n' "$plugin_file"
}

# ==============================================
# -- _gsr_detect_wp_theme
# -- Detect the WordPress theme style.css for this repo, scoped to the repo-named folder
# ==============================================
_gsr_detect_wp_theme () {
    local repo_basename theme_file
    repo_basename="$(basename "$PWD")"

    theme_file="$(grep -RIl --include='style.css' '^[[:space:]]*Theme Name:' "./${repo_basename}" 2>/dev/null | head -n 1)"

    if [[ -z $theme_file && -f "./style.css" ]]; then
        if grep -q '^[[:space:]]*Theme Name:' "./style.css" 2>/dev/null; then
            theme_file="./style.css"
        fi
    fi

    printf '%s\n' "$theme_file"
}

# ==============================================
# -- _gsr_confirm <prompt>
# -- y/N prompt; returns 0 on yes. Honors --yes (ASSUME_YES=1).
# ==============================================
_gsr_confirm () {
    local prompt="$1" reply
    if [[ ${ASSUME_YES:-0} -eq 1 ]]; then
        _gsr_loading2 "$prompt -> yes (--yes)"
        return 0
    fi
    if [[ ! -t 0 || ! -t 1 ]]; then
        _gsr_error "confirmation required but no TTY (pass --yes)"
        exit 2
    fi
    printf '%s (y/n) ' "$prompt"
    read -r reply || reply=""
    [[ $reply == [Yy]* ]]
}

# ==============================================
# -- _gsr_read_claude_manifest_version <file>
# -- Echo the version recorded in a Claude plugin or marketplace manifest.
# ==============================================
_gsr_read_claude_manifest_version () {
    python3 - "$1" <<'PY' 2>/dev/null
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
version = data.get("version", "")
if not isinstance(version, str):
    version = ""
entries = data.get("plugins")
if isinstance(entries, list):
    for entry in entries:
        if isinstance(entry, dict):
            entry_version = entry.get("version")
            if entry_version is not None and entry_version != version:
                version = "MISMATCH"
print(version)
PY
}

# ==============================================
# -- Writable version sources
# -- One inventory feeds both the drift check and the release writers, so the
# -- two can never cover a different set of files.
# -- Format: <type>|<path>|<value> (one per present writable source).
# ==============================================
_gsr_collect_version_sources () {
    local v

    if [[ -f VERSION ]]; then
        v="$(grep -m 1 -E '[^[:space:]]' VERSION 2>/dev/null | tr -d '[:space:]')"
        printf 'version_file|VERSION|%s\n' "$v"
    fi

    if [[ -f .claude-plugin/plugin.json ]]; then
        v="$(_gsr_read_claude_manifest_version .claude-plugin/plugin.json)"
        printf 'claude_plugin|.claude-plugin/plugin.json|%s\n' "$v"
    fi

    if [[ -f .claude-plugin/marketplace.json ]]; then
        v="$(_gsr_read_claude_manifest_version .claude-plugin/marketplace.json)"
        printf 'claude_marketplace|.claude-plugin/marketplace.json|%s\n' "$v"
    fi

    if [[ -f package.json ]] && grep -q -E '^[[:space:]]*"version"[[:space:]]*:' package.json; then
        if _gsr_have node; then
            v="$(node -p "require('./package.json').version" 2>/dev/null | tr -d '[:space:]')"
        else
            v="$(grep -m 1 -E '^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"[^"]*"' package.json 2>/dev/null | sed -E 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
        fi
        printf 'package_json|package.json|%s\n' "$v"
    fi

    if [[ -n $WP_PLUGIN_FILE ]] && grep -qi '^[[:space:]]*\*\{0,1\}[[:space:]]*Version[[:space:]]*:' "$WP_PLUGIN_FILE"; then
        v="$(grep -i -m 1 '^[[:space:]]*\*\{0,1\}[[:space:]]*Version[[:space:]]*:' "$WP_PLUGIN_FILE" 2>/dev/null | sed -E 's/^[[:space:]]*\*?[[:space:]]*Version[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')"
        printf 'plugin_header|%s|%s\n' "$WP_PLUGIN_FILE" "$v"
    fi

    if [[ -n $WP_THEME_FILE ]] && grep -qi '^[[:space:]]*Version:' "$WP_THEME_FILE"; then
        v="$(grep -i -m 1 '^[[:space:]]*Version[[:space:]]*:' "$WP_THEME_FILE" 2>/dev/null | sed -E 's/^[[:space:]]*Version[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')"
        printf 'theme_header|%s|%s\n' "$WP_THEME_FILE" "$v"
    fi
}

# ==============================================
# -- _gsr_require_writable_source
# -- A release must be able to write the version it tags. Detection-only sources
# -- (composer.json, pyproject.toml) cannot be written, so refuse rather than tag
# -- a version that no file records.
# ==============================================
_gsr_require_writable_source () {
    if [[ -n "$(_gsr_collect_version_sources)" ]]; then
        return 0
    fi
    _gsr_error "No writable version source found (expected VERSION, package.json, a plugin Version header, or a theme Version header)."
    printf '  Detection-only sources (composer.json, pyproject.toml) cannot be updated by a release.\n' >&2
    return 1
}

# ==============================================
# -- _gsr_check_version_drift <tag> [quiet]
# -- Compare every writable source against the last reachable tag.
# -- Returns 0 (clean), 1 (drift), or 2 (malformed value).
# -- A malformed value is never waivable; drift is waivable by the caller.
# ==============================================
_gsr_check_version_drift () {
    local tag="$1" quiet="${2:-}" expected type path value rc=0
    [[ -n $tag ]] || return 0
    expected="${tag#v}"

    while IFS='|' read -r type path value; do
        [[ -n $type ]] || continue
        if [[ ! $value =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            (( quiet )) || _gsr_error "[FAIL] $path has a malformed version '${value:-<empty>}' (expected X.Y.Z)"
            rc=2
            continue
        fi
        if [[ $value != "$expected" ]]; then
            (( quiet )) || _gsr_error "[FAIL] Version drift: $path is $value but the last tag is $tag (expects $expected)"
            [[ $rc -eq 0 ]] && rc=1
        fi
    done < <(_gsr_collect_version_sources)

    return "$rc"
}

# ==============================================
# -- _gsr_write_version_file <ver>
# ==============================================
_gsr_write_version_file () {
    local ver="$1"
    if ! printf '%s\n' "$ver" > VERSION; then
        _gsr_error "Failed to update VERSION file"
        return 1
    fi
    git add VERSION
    _gsr_success "Updated VERSION file to $ver"
    return 0
}

# ==============================================
# -- _gsr_write_package_json_version <ver>
# ==============================================
_gsr_write_package_json_version () {
    local ver="$1"
    if ! sed -i -E "0,/^[[:space:]]*\"version\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/s//  \"version\": \"${ver}\"/" package.json; then
        _gsr_error "Failed to update version field in package.json"
        return 1
    fi
    git add package.json
    _gsr_success "Updated package.json version to $ver"
    return 0
}

# ==============================================
# -- _gsr_write_header_version <path> <ver>
# -- Rewrites a plugin docblock `Version:` or a theme `Version:` header.
# ==============================================
_gsr_write_header_version () {
    local path="$1" ver="$2"
    if ! sed -i -E "s|^([[:space:]]*\*?[[:space:]]*)Version[[:space:]]*:.*$|\1Version: ${ver}|" "$path"; then
        _gsr_error "Failed to update the version header in $path"
        return 1
    fi
    git add "$path"
    _gsr_success "Updated version header to $ver in $path"
    return 0
}

# ==============================================
# -- _gsr_write_claude_manifest_version <path> <ver>
# -- Rewrite plugin.json, or marketplace.json (top level and every entry).
# ==============================================
_gsr_write_claude_manifest_version () {
    local path="$1" ver="$2" tmp
    tmp="$(mktemp)"
    if ! python3 - "$path" "$ver" "$tmp" <<'PY'
import json
import sys

path, version, target = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
if not isinstance(data, dict):
    raise SystemExit("manifest is not a JSON object")
data["version"] = version
entries = data.get("plugins")
if isinstance(entries, list):
    for entry in entries:
        if isinstance(entry, dict):
            entry["version"] = version
with open(target, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY
    then
        rm -f -- "$tmp"
        _gsr_error "Failed to update the version in $path"
        return 1
    fi
    if ! mv -- "$tmp" "$path"; then
        rm -f -- "$tmp"
        _gsr_error "Failed to replace $path"
        return 1
    fi
    git add "$path"
    _gsr_success "Updated $path version to $ver"
    return 0
}

# ==============================================
# -- _gsr_finalize_changelog <ver>
# -- Promote the content under "## Unreleased" to "## v<ver> - <date>".
# -- Idempotent: an empty Unreleased section or an existing heading is a no-op.
# ==============================================
_gsr_finalize_changelog () {
    local ver="$1" date heading tmp has_content
    [[ -f CHANGELOG.md ]] || return 0
    date="$(date +%Y-%m-%d)"
    heading="## v${ver} - ${date}"

    if ! grep -qx '## Unreleased' CHANGELOG.md; then
        _gsr_error "CHANGELOG.md has no '## Unreleased' heading"
        return 1
    fi
    if grep -qF "$heading" CHANGELOG.md; then
        _gsr_debug "CHANGELOG.md already has $heading"
        return 0
    fi

    has_content="$(awk '/^## Unreleased$/{inside=1; next} inside && /^## /{exit} inside && NF{print; exit}' CHANGELOG.md)"
    if [[ -z $has_content ]]; then
        _gsr_warning "CHANGELOG.md '## Unreleased' is empty; no release section added"
        return 0
    fi

    tmp="$(mktemp)"
    if ! awk -v heading="$heading" '
        /^## Unreleased$/ && !done { print; print ""; print heading; done=1; next }
        { print }
    ' CHANGELOG.md > "$tmp"; then
        rm -f -- "$tmp"
        _gsr_error "Failed to write the finalized CHANGELOG.md"
        return 1
    fi
    if ! mv -- "$tmp" CHANGELOG.md; then
        rm -f -- "$tmp"
        _gsr_error "Failed to replace CHANGELOG.md"
        return 1
    fi
    git add CHANGELOG.md
    _gsr_success "Finalized CHANGELOG.md as $heading"
    return 0
}

# ==============================================
# -- _gsr_update_all_versions <tag>
# -- Write the release version to every source the collector found, so the
# -- validation set and the written set are always the same files.
# ==============================================
_gsr_update_all_versions () {
    local tag="$1" ver="${1#v}" type path value wrote=0

    while IFS='|' read -r type path value; do
        [[ -n $type ]] || continue
        case "$type" in
            version_file) _gsr_write_version_file "$ver" || return 1 ;;
            package_json) _gsr_write_package_json_version "$ver" || return 1 ;;
            plugin_header|theme_header) _gsr_write_header_version "$path" "$ver" || return 1 ;;
            claude_plugin|claude_marketplace) _gsr_write_claude_manifest_version "$path" "$ver" || return 1 ;;
            *) _gsr_error "Unknown version source type: $type"; return 1 ;;
        esac
        wrote=1
    done < <(_gsr_collect_version_sources)

    if (( wrote == 0 )); then
        _gsr_warning "No writable version source found; nothing to update"
    fi

    _gsr_finalize_changelog "$ver" || return 1
    return 0
}

# ==============================================
# -- _gsr_commit_release_version_bump <tag>
# -- Create a temporary version bump commit that will be folded into the release commit
# ==============================================
_gsr_commit_release_version_bump () {
    local RELEASE_TAG="$1"
    local RELEASE_VERSION="${RELEASE_TAG#v}"
    local BUMP_COMMIT_MSG="chore: bump version to ${RELEASE_VERSION}"
    local base after first

    if git diff --cached --quiet --exit-code; then
        _gsr_debug "No staged version changes detected. Skipping temporary version bump commit."
        BUMP_HEAD=$(git rev-parse HEAD)
        return 0
    fi

    base=$(git rev-parse HEAD)
    if ! git commit -m "$BUMP_COMMIT_MSG"; then
        _gsr_error "Failed to create temporary version bump commit"
        return 1
    fi

    after=$(git rev-parse HEAD)
    # The bump commit is the first commit after the starting point. A hook that
    # commits during the release adds commits after it, which BUMP_HEAD exposes
    # to the pre-reset recheck.
    first=$(git rev-list --reverse "$base..$after" 2>/dev/null | head -n 1)
    BUMP_HEAD="${first:-$after}"

    _gsr_success "Created temporary version bump commit: $BUMP_COMMIT_MSG"
    return 0
}

# ==============================================
# -- _gsr_collect_commit_messages <range>
# -- Deduplicated "(shorthash) subject" lines for the commits in <range>
# ==============================================
_gsr_collect_commit_messages () {
    local range="$1"
    git log --oneline "$range" 2>/dev/null | awk '{msg=substr($0, index($0,$2)); if (!seen[msg]++) print "(" $1 ") " msg}'
}

# ==============================================
# -- _gsr_choose_bump <bump> <minor_tag> <major_tag>
# -- Echo "minor" | "major" | "" (cancel); honors --bump (no prompt).
# ==============================================
_gsr_choose_bump () {
    local bump="$1" minor_tag="$2" major_tag="$3" reply

    if [[ -n $bump ]]; then
        printf '%s\n' "$bump"
        return 0
    fi

    {
        printf ' * Select release type:\n'
        printf '  (i) minor  (%s)\n' "$minor_tag"
        printf '  (a) major  (%s)\n' "$major_tag"
        printf '  (c) cancel\n\n'
        printf 'Select [i/a/c]: '
    } >&2

    read -r -n 1 reply || reply=""
    printf '\n' >&2

    case "$reply" in
        i) printf 'minor\n' ;;
        a) printf 'major\n' ;;
        *) printf '\n' ;;
    esac
}

# ==============================================
# -- _gsr_push_prompt <push_mode> <assume_yes> <tag>
# -- Force-push + push tags, honoring --push/--no-push/--yes.
# ==============================================
_gsr_push_prompt () {
    local push_mode="$1" assume_yes="$2" tag="$3" do_push=0

    case "$push_mode" in
        push) do_push=1 ;;
        nopush) do_push=0 ;;
        *)
            if [[ $assume_yes -eq 1 ]]; then
                do_push=0
            elif _gsr_confirm "Push tag and commit with --force?"; then
                do_push=1
            fi
            ;;
    esac

    if [[ $do_push -eq 1 ]]; then
        _gsr_loading "Pushing with --force-with-lease..."
        if ! git push --force-with-lease; then
            _gsr_error "Failed to push the branch"
            return 1
        fi
        _gsr_loading "Pushing tag $tag..."
        if ! git push origin "$tag"; then
            _gsr_error "Failed to push tag $tag"
            return 1
        fi
        _gsr_success "Release $tag pushed successfully."
    else
        _gsr_warning "Not pushed. To push manually run:"
        echo "  git push --force-with-lease && git push origin $tag"
    fi
    return 0
}

# ==============================================
# -- _gsr_check_divergence <skip> <main_arg>
# -- Hard-stop when origin/<main> has commits not reachable from the current branch.
# ==============================================
_gsr_check_divergence () {
    local skip="$1" main_arg="$2" main current ref behind

    if [[ $skip -eq 1 ]]; then
        _gsr_debug "Divergence check skipped (--skip-divergence-check)."
        return 0
    fi

    current="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"

    main="$main_arg"
    if [[ -z $main ]]; then
        main="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
        if [[ -z $main ]]; then
            if git show-ref --verify --quiet refs/heads/main || git show-ref --verify --quiet refs/remotes/origin/main; then
                main="main"
            elif git show-ref --verify --quiet refs/heads/master || git show-ref --verify --quiet refs/remotes/origin/master; then
                main="master"
            fi
        fi
    fi

    if [[ -z $main ]]; then
        _gsr_warning "Divergence check skipped: could not detect a main branch (use --main BRANCH to set one)"
        return 0
    fi

    if git show-ref --verify --quiet "refs/remotes/origin/$main"; then
        ref="origin/$main"
    elif git show-ref --verify --quiet "refs/heads/$main"; then
        ref="$main"
    else
        _gsr_warning "Divergence check skipped: could not resolve '$main' (no local or origin/$main ref)"
        return 0
    fi

    # Already on main: nothing to diverge from.
    if [[ -n $current && $current == "$main" ]]; then
        return 0
    fi

    behind="$(git rev-list --count "HEAD..$ref" 2>/dev/null)"
    if [[ -n $behind && $behind -gt 0 ]]; then
        _gsr_error "[FAIL] Branch is diverged from $ref ($behind commit(s) on $ref not in ${current:-HEAD}). Merge or rebase $ref into this branch first, or pass --skip-divergence-check if this is intentional."
        return 1
    fi

    _gsr_success "[PASS] No divergence from $ref"
    return 0
}

# ==============================================
# -- Detection state (globals so --status and the main flow share one detector)
# ==============================================
CURRENT_VERSION=""
CURRENT_VERSION_SOURCE=""
VERSION_HEADER_FILE=""
WP_PLUGIN_FILE=""
WP_PLUGIN_FALLBACK_FILE=""
WP_THEME_FILE=""
REPO_BASENAME=""
RELEASE_MARKER=""
SAVED_HEAD=""
BUMP_HEAD=""
IGNORE_PGF_LOCK=0
ALLOW_VERSION_DRIFT=0
DRIFT_FAILED=0

# ==============================================
# -- _gsr_detect_current_version
# -- Sets CURRENT_VERSION / CURRENT_VERSION_SOURCE. Returns 0 when found.
# -- Tier order: package.json, WP plugin, WP theme, VERSION file.
# ==============================================
_gsr_detect_current_version () {
    local v

    CURRENT_VERSION=""
    CURRENT_VERSION_SOURCE=""
    VERSION_HEADER_FILE=""

    # Tier 1: package.json version field (Node.js apps). Preferred over VERSION.
    if [[ -f package.json ]]; then
        if _gsr_have node; then
            v="$(node -p "require('./package.json').version" 2>/dev/null | tr -d '[:space:]')"
        else
            v="$(grep -m 1 -E '^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"[^"]*"' package.json 2>/dev/null | sed -E 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
        fi
        if [[ -n $v ]]; then
            CURRENT_VERSION="$v"
            CURRENT_VERSION_SOURCE="package.json"
        fi
    fi

    # Tier 2: WordPress plugin Version header.
    if [[ -z $CURRENT_VERSION && -n $WP_PLUGIN_FILE ]]; then
        VERSION_HEADER_FILE="$WP_PLUGIN_FILE"
        v="$(grep -i -m 1 '^[[:space:]]*\*\{0,1\}[[:space:]]*Version[[:space:]]*:' "$VERSION_HEADER_FILE" 2>/dev/null | sed -E 's/^[[:space:]]*\*?[[:space:]]*Version[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')"
        if [[ -n $v ]]; then
            CURRENT_VERSION="$v"
            CURRENT_VERSION_SOURCE="plugin header ($VERSION_HEADER_FILE)"
        fi
    fi

    # Tier 3: WordPress theme Version header.
    if [[ -z $CURRENT_VERSION && -n $WP_THEME_FILE ]]; then
        v="$(grep -i -m 1 '^[[:space:]]*Version[[:space:]]*:' "$WP_THEME_FILE" 2>/dev/null | sed -E 's/^[[:space:]]*Version[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')"
        if [[ -n $v ]]; then
            CURRENT_VERSION="$v"
            CURRENT_VERSION_SOURCE="theme header ($WP_THEME_FILE)"
        fi
    fi

    # Tier 4: VERSION file (last detection tier).
    if [[ -z $CURRENT_VERSION && -f VERSION ]]; then
        v="$(grep -m 1 -E '[^[:space:]]' VERSION 2>/dev/null | tr -d '[:space:]')"
        if [[ -n $v ]]; then
            CURRENT_VERSION="$v"
            CURRENT_VERSION_SOURCE="VERSION"
        fi
    fi

    # Tier 5: composer.json (detection only — a release cannot write it).
    if [[ -z $CURRENT_VERSION && -f composer.json ]]; then
        v="$(grep -m 1 -E '^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"[^"]*"' composer.json 2>/dev/null \
            | sed -E 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
        if [[ -n $v ]]; then
            CURRENT_VERSION="$v"
            CURRENT_VERSION_SOURCE="composer.json (detection only)"
        fi
    fi

    # Tier 6: pyproject.toml (detection only — a release cannot write it).
    if [[ -z $CURRENT_VERSION && -f pyproject.toml ]]; then
        v="$(grep -m 1 -E '^[[:space:]]*version[[:space:]]*=[[:space:]]*"[^"]*"' pyproject.toml 2>/dev/null \
            | sed -E 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/')"
        if [[ -n $v ]]; then
            CURRENT_VERSION="$v"
            CURRENT_VERSION_SOURCE="pyproject.toml (detection only)"
        fi
    fi

    [[ -n $CURRENT_VERSION ]]
}

# ==============================================
# -- PGF integration: plans dir, plan lock, release marker, mutation guards
# -- Ported from this repo's previous pgf-release.sh so the imported helper
# -- keeps release/plan mutual exclusion and concurrent-mutation protection.
# ==============================================

_gsr_hostname () { hostname 2>/dev/null || uname -n 2>/dev/null || printf 'unknown'; }

# -- _gsr_plans_dir : echo <repo-root>/plans, or return 1 when absent
_gsr_plans_dir () {
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
    [[ -d $root/plans ]] || return 1
    printf '%s/plans\n' "$root"
}

# -- _gsr_pgf_lock_holder <lock-file>
# -- Print "<plan> (owner: <owner>, host: <host>, since: <started>)";
# -- return 1 when the file is missing or has no PLAN field.
_gsr_pgf_lock_holder () {
    local file="${1:-}" plan owner host started
    [[ -f $file ]] || return 1
    plan=$(grep -m1 '^PLAN=' "$file" 2>/dev/null | cut -d= -f2-)
    [[ -n $plan ]] || return 1
    owner=$(grep -m1 '^OWNER=' "$file" 2>/dev/null | cut -d= -f2-)
    host=$(grep -m1 '^HOST=' "$file" 2>/dev/null | cut -d= -f2-)
    started=$(grep -m1 '^STARTED=' "$file" 2>/dev/null | cut -d= -f2-)
    printf '%s (owner: %s, host: %s, since: %s)\n' \
        "$plan" "${owner:-?}" "${host:-?}" "${started:-?}"
}

# -- Release marker: <plans-dir>/.pgf.release.lock
# -- Presence means "a release is rewriting history". It is runtime state,
# -- never committed, and cleared only by the release that owns it or by an
# -- explicit `pgf unlock --force`.
_gsr_release_marker_path () {
    printf '%s/.pgf.release.lock\n' "${1%/}"
}

_gsr_release_marker_holder () {
    local file="${1:-}" repo owner host started
    [[ -f $file ]] || return 1
    repo=$(grep -m1 '^REPO=' "$file" 2>/dev/null | cut -d= -f2-)
    [[ -n $repo ]] || return 1
    owner=$(grep -m1 '^OWNER=' "$file" 2>/dev/null | cut -d= -f2-)
    host=$(grep -m1 '^HOST=' "$file" 2>/dev/null | cut -d= -f2-)
    started=$(grep -m1 '^STARTED=' "$file" 2>/dev/null | cut -d= -f2-)
    printf '%s (owner: %s, host: %s, since: %s)\n' \
        "$repo" "${owner:-?}" "${host:-?}" "${started:-?}"
}

# -- _gsr_release_marker_acquire <plans-dir> : create the marker atomically
_gsr_release_marker_acquire () {
    local plans_dir="${1:-}" path tmp repo owner holder head
    path=$(_gsr_release_marker_path "$plans_dir")
    if [[ -e $path ]]; then
        if holder=$(_gsr_release_marker_holder "$path"); then
            _gsr_error "A release is already in progress: $holder"
        else
            _gsr_error "A release is already in progress: $path (unreadable marker)"
        fi
        printf '  Finish it, or clear it with: pgf unlock --force\n' >&2
        return 1
    fi

    repo=$(basename -- "$PWD")
    owner="${PGF_LOCK_OWNER:-${USER:-unknown}@$(_gsr_hostname)}"
    head=$(git rev-parse HEAD 2>/dev/null || true)
    tmp=$(mktemp "$plans_dir/.pgf.release.lock.XXXXXX") || {
        _gsr_error "Cannot create a release lock in $plans_dir"
        return 1
    }
    chmod 600 "$tmp" 2>/dev/null || true
    {
        printf 'PGF_RELEASE_LOCK_VERSION=1\n'
        printf 'KIND=release\n'
        printf 'REPO=%s\n' "$repo"
        printf 'OWNER=%s\n' "$owner"
        printf 'HOST=%s\n' "$(_gsr_hostname)"
        printf 'PID=%s\n' "$$"
        printf 'STARTED=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'HEAD=%s\n' "$head"
    } > "$tmp" || { rm -f -- "$tmp"; _gsr_error "Failed to write $tmp"; return 1; }

    if ! ln -- "$tmp" "$path" 2>/dev/null; then
        rm -f -- "$tmp"
        if holder=$(_gsr_release_marker_holder "$path"); then
            _gsr_error "A release is already in progress: $holder"
        else
            _gsr_error "Failed to acquire the release lock: $path"
        fi
        return 1
    fi
    rm -f -- "$tmp"
    RELEASE_MARKER="$path"
    _gsr_success "[OK] Release lock acquired: $path"
    return 0
}

# -- _gsr_release_marker_release : remove the marker only when this process owns it
_gsr_release_marker_release () {
    local path="${RELEASE_MARKER:-}" pid
    [[ -n $path && -e $path ]] || return 0
    pid=$(grep -m1 '^PID=' "$path" 2>/dev/null | cut -d= -f2-)
    [[ $pid == "$$" ]] || return 0
    rm -f -- "$path" || return 1
    RELEASE_MARKER=""
    _gsr_success "[OK] Release lock released: $path"
    return 0
}

# -- _gsr_release_marker_on_signal : clean up and leave without resuming the rewrite
_gsr_release_marker_on_signal () {
    _gsr_release_marker_release
    exit 130
}

# -- _gsr_recheck_mutation [<expected-head>]
# -- Refuse to continue a release when the repository changed under us.
_gsr_recheck_mutation () {
    local expected="${1:-}" root gitdir marker_rel dirty state head
    root=$(git rev-parse --show-toplevel 2>/dev/null) || {
        _gsr_error "[FAIL] Mutation recheck: not inside a git work tree"
        return 1
    }
    gitdir=$(git rev-parse --git-dir 2>/dev/null) || gitdir="$root/.git"
    [[ $gitdir == /* ]] || gitdir="$root/$gitdir"

    if [[ -e $root/plans/.pgf.lock ]] && (( IGNORE_PGF_LOCK == 0 )); then
        _gsr_error "[FAIL] A PGF execution lock appeared during the release ($(_gsr_pgf_lock_holder "$root/plans/.pgf.lock" || printf 'unreadable lock'))"
        echo "  Release it with: pgf unlock <plan>, then re-run the release." >&2
        return 1
    fi

    if [[ -e $gitdir/index.lock ]]; then
        _gsr_error "[FAIL] The git index is locked ($gitdir/index.lock) — another git process is running"
        echo "  Wait for it to finish, or remove a stale lock, then re-run the release." >&2
        return 1
    fi

    for state in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
        if [[ -e $gitdir/$state ]]; then
            _gsr_error "[FAIL] A git operation is in progress ($state) — refusing to rewrite history"
            echo "  Finish or abort it, then re-run the release." >&2
            return 1
        fi
    done

    marker_rel="plans/.pgf.release.lock"
    if [[ -n ${RELEASE_MARKER:-} && ${RELEASE_MARKER} == "$root/"* ]]; then
        marker_rel="${RELEASE_MARKER#"$root"/}"
    fi
    dirty=$(git -C "$root" status --porcelain 2>/dev/null | grep -v -x -F -e "?? $marker_rel")
    if (( IGNORE_PGF_LOCK )); then
        dirty=$(printf '%s\n' "$dirty" | grep -v -x -F -e "?? plans/.pgf.lock")
    fi
    if [[ -n $dirty ]]; then
        _gsr_error "[FAIL] The working tree changed during the release:"
        printf '%s\n' "$dirty" | sed 's/^/  /' >&2
        echo "  Commit or remove those paths, then re-run the release." >&2
        return 1
    fi

    if [[ -n $expected ]]; then
        head=$(git rev-parse HEAD 2>/dev/null || true)
        if [[ $head != "$expected" ]]; then
            _gsr_error "[FAIL] A commit landed during the release (HEAD moved from $expected to ${head:-?})"
            echo "  Re-run the release; nothing was reset, tagged, or pushed." >&2
            return 1
        fi
    fi
    return 0
}

# -- _gsr_restore_saved_head : --hard restore for a failure before the squash reset
_gsr_restore_saved_head () {
    local saved="${SAVED_HEAD:-}"
    [[ -n $saved ]] || return 0
    if git reset --hard "$saved" >/dev/null 2>&1; then
        _gsr_warning "Release aborted — restored the repository to $saved"
    else
        _gsr_error "Could not restore $saved — inspect the repository before retrying"
    fi
}

# -- _gsr_restore_after_reset : --mixed restore for a failure after git reset --soft
_gsr_restore_after_reset () {
    local saved="${SAVED_HEAD:-}"
    [[ -n $saved ]] || return 0
    if git reset --mixed "$saved" >/dev/null 2>&1; then
        _gsr_warning "Release aborted after the squash reset — restored the branch to $saved"
        echo "  saved head: $saved (working tree left as-is for inspection)" >&2
    else
        _gsr_error "Could not restore $saved — the branch may still be rewound"
    fi
}

# -- _gsr_commit_count : commits since the latest tag (whole history when none)
_gsr_commit_count () {
    local tag n
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        printf '0\n'
        return 0
    fi
    tag="$(_gsr_latest_tag)"
    if [[ -n $tag ]]; then
        n=$(git rev-list --count "${tag}..HEAD" 2>/dev/null || true)
    else
        n=$(git rev-list --count HEAD 2>/dev/null || true)
    fi
    [[ $n =~ ^[0-9]+$ ]] || n=0
    printf '%s\n' "$n"
}

# -- _gsr_squash_threshold : PGF_SQUASH_THRESHOLD, plans/pgf.config, then 20
_gsr_squash_threshold () {
    local root cfg value=""
    root=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -n $root ]]; then
        cfg="${root}/plans/pgf.config"
    else
        cfg="./plans/pgf.config"
    fi
    if [[ -n ${PGF_SQUASH_THRESHOLD:-} ]]; then
        value="$PGF_SQUASH_THRESHOLD"
    elif [[ -f $cfg ]]; then
        value=$(sed -n 's/^[[:space:]]*SQUASH_THRESHOLD[[:space:]]*=[[:space:]]*//p' "$cfg" 2>/dev/null | head -n 1)
        value="${value%%#*}"
        value="${value%"${value##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%\"}"; value="${value#\"}"
        value="${value%\'}"; value="${value#\'}"
    fi
    if [[ -z $value ]]; then
        printf '20\n'
        return 0
    fi
    if [[ ! $value =~ ^[0-9]+$ ]] || (( value < 1 )); then
        _gsr_warning "Invalid squash threshold '${value}' (expected a positive integer); using 20" >&2
        printf '20\n'
        return 0
    fi
    printf '%s\n' "$value"
}

# -- _gsr_squash_verdict : yes/no; a version-less repo has no release to cut
_gsr_squash_verdict () {
    local threshold count
    if [[ -z $CURRENT_VERSION ]]; then
        printf 'no\n'
        return 0
    fi
    threshold="$(_gsr_squash_threshold)"
    [[ $threshold =~ ^[0-9]+$ ]] || threshold=20
    count="$(_gsr_commit_count)"
    if (( count >= threshold )); then
        printf 'yes\n'
    else
        printf 'no\n'
    fi
}

# -- _gsr_status : compact one-line gate status (read-only)
_gsr_status () {
    local tag mismatch="no" action="none" tag_clean count squash
    WP_PLUGIN_FILE="$(_gsr_detect_wp_plugin)"
    WP_THEME_FILE="$(_gsr_detect_wp_theme)"
    _gsr_detect_current_version || true
    tag="$(_gsr_latest_tag)"

    if [[ -n $CURRENT_VERSION ]]; then
        if [[ -z $tag ]]; then
            mismatch="yes"
            action="release"
        else
            tag_clean="${tag#v}"
            if [[ $CURRENT_VERSION != "$tag_clean" ]]; then
                mismatch="yes"
                action="release"
            fi
        fi
    fi

    # -- Any writable source that disagrees with the tag is drift, even when the
    # -- highest-precedence source matches.
    if [[ -n $tag ]]; then
        local drift_rc=0
        _gsr_check_version_drift "$tag" quiet || drift_rc=$?
        if (( drift_rc != 0 )); then
            mismatch="yes"
            action="release"
        fi
    fi

    count="$(_gsr_commit_count)"
    squash="$(_gsr_squash_verdict)"

    printf 'VERSION: %s (%s)  TAG: %s  MISMATCH: %s  ACTION: %s  COMMITS: %s  SQUASH: %s\n' \
        "${CURRENT_VERSION:-none}" \
        "${CURRENT_VERSION_SOURCE:-none}" \
        "${tag:-none}" \
        "$mismatch" \
        "$action" \
        "$count" \
        "$squash"
}

# -- _gsr_release_commit <tag> <messages> : soft-reset to the last tag and squash
_gsr_release_commit () {
    local tag="$1" msgs="$2" tag_commit bump_head
    tag_commit=$(git rev-list -n 1 "$LAST_TAG" 2>/dev/null)
    if [[ -z $tag_commit ]]; then
        _gsr_error "Could not resolve commit for tag $LAST_TAG"
        return 1
    fi
    bump_head="${BUMP_HEAD:-$(git rev-parse HEAD)}"
    if ! _gsr_recheck_mutation "$bump_head"; then
        _gsr_error "A commit landed during the release — re-run the release. The version bump is left in place."
        return 1
    fi
    if ! git reset --soft "$tag_commit"; then
        _gsr_error "Failed to soft-reset to $LAST_TAG"
        _gsr_restore_saved_head
        return 1
    fi
    if ! git commit -m "Release ${tag}

${msgs}"; then
        _gsr_error "Failed to create the release commit"
        _gsr_restore_after_reset
        return 1
    fi
    # Annotated, with the same folded list as the commit: the tag is what a host
    # records as its revision and what an operator reads later, so it has to say
    # what shipped, not just point at a commit.
    if ! git tag -a "$tag" -m "Release ${tag}

${msgs}"; then
        _gsr_error "Failed to create tag $tag"
        _gsr_restore_after_reset
        return 1
    fi
    _gsr_success "[OK] Tagged commit as $tag"
    return 0
}

# ==============================================
# -- main
# ==============================================
main () {
    local DETECT_ONLY=0 FORCE=0 SQUASH_ONLY=0 INIT=0 REPO=""
    local STATUS_ONLY=0
    local ASSUME_YES=0 BUMP="" PUSH_MODE=""
    local MAIN_BRANCH="" SKIP_DIVERGENCE=0
    local DETECTION_FAILED=0
    local DRIFT_FAILED=0
    local INITIAL_RELEASE=0
    local LAST_TAG="" LAST_TAG_COMMIT=""
    local TAG_CLEAN="" TAG_MAJOR="" TAG_MINOR="" TAG_PATCH="" TAG_PREFIX=""
    local MINOR_VERSION MAJOR_VERSION MINOR_TAG MAJOR_TAG
    local COMMIT_MSGS COMMIT_COUNT

    # -- Parse options --
    while (( $# )); do
        case "$1" in
            -h|--help) usage; return 0 ;;
            -d|--detect) DETECT_ONLY=1 ;;
            --status) STATUS_ONLY=1 ;;
            --ignore-pgf-lock) IGNORE_PGF_LOCK=1 ;;
            --allow-version-drift) ALLOW_VERSION_DRIFT=1 ;;
            -f|--force) FORCE=1 ;;
            -s|--squash) SQUASH_ONLY=1 ;;
            -i|--init) INIT=1 ;;
            -r|--repo) shift; REPO="${1:-}"; [[ -n $REPO ]] || { _gsr_error "Missing value for --repo"; return 2; } ;;
            --repo=*) REPO="${1#*=}" ;;
            -y|--yes) ASSUME_YES=1 ;;
            --bump) BUMP="${2:-}"; shift ;;
            --bump=*) BUMP="${1#*=}" ;;
            -p|--push) PUSH_MODE="push" ;;
            --no-push) PUSH_MODE="nopush" ;;
            --main) MAIN_BRANCH="${2:-}"; shift ;;
            --main=*) MAIN_BRANCH="${1#*=}" ;;
            --skip-divergence-check) SKIP_DIVERGENCE=1 ;;
            *) _gsr_error "Unknown option: $1"; usage >&2; return 2 ;;
        esac
        shift
    done

    if [[ -n $BUMP && $BUMP != minor && $BUMP != major ]]; then
        _gsr_error "--bump must be 'minor' or 'major' (got '$BUMP')"
        return 2
    fi

    if [[ -n $REPO ]]; then
        if ! cd -- "$REPO"; then
            _gsr_error "Could not enter repository directory: $REPO"
            return 1
        fi
    fi

    # -- --status is the PGF Version & Release Gate's read-only source of truth.
    if [[ $STATUS_ONLY -eq 1 ]]; then
        _gsr_status
        return 0
    fi

    _gsr_loading "Running git-squash-release detections..."

    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        _gsr_success "[PASS] Inside a git repository"
    else
        _gsr_error "[FAIL] Inside a git repository"
        DETECTION_FAILED=1
    fi

    if git rev-parse --verify HEAD >/dev/null 2>&1; then
        _gsr_success "[PASS] Repository has at least one commit"
    else
        _gsr_error "[FAIL] Repository has at least one commit"
        DETECTION_FAILED=1
    fi

    LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null)"
    if [[ -n $LAST_TAG ]]; then
        _gsr_success "[PASS] Found latest tag: $LAST_TAG"
    else
        if [[ $DETECT_ONLY -eq 1 ]]; then
            _gsr_warning "[FAIL] Found latest tag"
        elif [[ $INIT -eq 1 ]]; then
            _gsr_warning "[SKIP] Found latest tag (init mode does not require tags)"
        else
            _gsr_warning "[FAIL] Found latest tag"
            if _gsr_confirm "No tags found. Create initial release 0.0.1 and squash commit history?"; then
                INITIAL_RELEASE=1
                _gsr_success "Initial release mode enabled (will squash history and tag 0.0.1)"
            else
                _gsr_error "Initial tag required. Aborting."
                DETECTION_FAILED=1
            fi
        fi
    fi

    if [[ -n $LAST_TAG ]]; then
        LAST_TAG_COMMIT="$(git rev-list -n 1 "$LAST_TAG" 2>/dev/null)"
        if [[ -n $LAST_TAG_COMMIT ]]; then
            _gsr_success "[PASS] Resolved latest tag to commit: $LAST_TAG_COMMIT"
        else
            _gsr_error "[FAIL] Resolved latest tag to commit"
            DETECTION_FAILED=1
        fi
    fi

    if [[ -n $LAST_TAG ]]; then
        TAG_CLEAN="${LAST_TAG#v}"
        if [[ "$TAG_CLEAN" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            _gsr_success "[PASS] Latest tag is semver compatible: $LAST_TAG"
        else
            _gsr_error "[FAIL] Latest tag is semver compatible (expected vX.Y.Z or X.Y.Z, got $LAST_TAG)"
            DETECTION_FAILED=1
        fi
    fi

    if [[ -n $LAST_TAG ]]; then
        COMMIT_COUNT="$(git rev-list --count "$LAST_TAG..HEAD" 2>/dev/null)"
        if [[ -n $COMMIT_COUNT && $COMMIT_COUNT -gt 0 ]]; then
            _gsr_success "[PASS] Commits found since $LAST_TAG: $COMMIT_COUNT"
        else
            _gsr_error "[FAIL] Commits found since $LAST_TAG"
            DETECTION_FAILED=1
        fi
    fi

    # -- PGF execution lock gate: never squash a plan session's commits away.
    # -- Runs before the cleanliness check so a lock (and its untracked files) is
    # -- reported as the reason, not as a dirty tree.
    local plans_dir lock_file holder plan_id
    if plans_dir=$(_gsr_plans_dir); then
        lock_file="$plans_dir/.pgf.lock"
        if [[ -e $lock_file ]]; then
            if holder=$(_gsr_pgf_lock_holder "$lock_file"); then
                if (( IGNORE_PGF_LOCK )); then
                    _gsr_warning "PGF execution lock held (plan $holder) — ignored via --ignore-pgf-lock"
                else
                    _gsr_error "[FAIL] No PGF execution lock held (plan $holder)"
                    plan_id="${holder%% *}"
                    printf '  Release it with: pgf unlock %s\n' "$plan_id" >&2
                    printf '  Or re-run with --ignore-pgf-lock only when no session is active.\n' >&2
                    DETECTION_FAILED=1
                fi
            else
                _gsr_error "[FAIL] No PGF execution lock held (malformed lock: $lock_file)"
                printf '  Remove it with: pgf unlock --force\n' >&2
                DETECTION_FAILED=1
            fi
        else
            _gsr_success "[PASS] No PGF execution lock held"
        fi
    else
        _gsr_warning "[SKIP] No plans directory"
    fi

    if [[ -z "$(git status --porcelain 2>/dev/null)" ]]; then
        _gsr_success "[PASS] Working tree is clean"
    else
        _gsr_error "[FAIL] Working tree is not clean — unstaged changes present"
        DETECTION_FAILED=1
    fi

    if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        _gsr_success "[PASS] Current branch has an upstream configured"
    else
        _gsr_error "[FAIL] Current branch has an upstream configured"
        DETECTION_FAILED=1
    fi

    # Tier 2: Detect a standard WordPress plugin header, scoped to the repo-named folder.
    REPO_BASENAME="$(basename "$PWD")"
    WP_PLUGIN_FALLBACK_FILE="./${REPO_BASENAME}.php"
    WP_PLUGIN_FILE="$(_gsr_detect_wp_plugin)"

    if [[ -n $WP_PLUGIN_FILE ]]; then
        if [[ $WP_PLUGIN_FILE == "$WP_PLUGIN_FALLBACK_FILE" ]]; then
            _gsr_success "[PASS] WordPress plugin detected (fallback filename): $WP_PLUGIN_FILE"
        else
            _gsr_success "[PASS] WordPress plugin detected (header): $WP_PLUGIN_FILE"
        fi
    else
        if [[ $DETECT_ONLY -eq 1 ]]; then
            _gsr_warning "[FAIL] WordPress plugin not detected (no Plugin Name header in ./${REPO_BASENAME}/ or repo root)"
        else
            _gsr_error "[FAIL] WordPress plugin not detected (no Plugin Name header in ./${REPO_BASENAME}/ or repo root)"
        fi
    fi

    WP_THEME_FILE="$(_gsr_detect_wp_theme)"
    if [[ -n $WP_THEME_FILE ]]; then
        _gsr_success "[PASS] WordPress theme detected: $WP_THEME_FILE"
    else
        if [[ $DETECT_ONLY -eq 1 ]]; then
            _gsr_warning "[FAIL] WordPress theme not detected (no Theme Name style.css in ./${REPO_BASENAME}/ or repo root)"
        else
            _gsr_error "[FAIL] WordPress theme not detected (no Theme Name style.css in ./${REPO_BASENAME}/ or repo root)"
        fi
    fi

    # Version source exists: package.json, VERSION, a detected WordPress plugin/theme,
    # or a detection-only composer.json / pyproject.toml (which cannot be written).
    if [[ -f package.json || -f VERSION || -n $WP_PLUGIN_FILE || -n $WP_THEME_FILE || -f composer.json || -f pyproject.toml ]]; then
        _gsr_success "[PASS] Version source exists (package.json, VERSION file, WordPress plugin/theme, composer.json, or pyproject.toml)"
    else
        if [[ $DETECT_ONLY -eq 1 ]]; then
            _gsr_warning "[FAIL] Version source exists (expected package.json, VERSION file, WordPress plugin/theme, composer.json, or pyproject.toml)"
        else
            _gsr_error "[FAIL] Version source exists (expected package.json, VERSION file, WordPress plugin/theme, composer.json, or pyproject.toml)"
        fi
    fi

    # Tier 1-4: one detector shared with --status.
    _gsr_detect_current_version || true

    if [[ -f .claude-plugin/plugin.json || -f .claude-plugin/marketplace.json ]] && ! _gsr_have python3; then
        _gsr_error "[FAIL] python3 is required to read and write the Claude manifests"
        DETECTION_FAILED=1
    fi

    if [[ -n $CURRENT_VERSION ]]; then
        _gsr_success "[PASS] Current version detected from ${CURRENT_VERSION_SOURCE}: ${CURRENT_VERSION}"
    else
        if [[ $DETECT_ONLY -eq 1 ]]; then
            _gsr_warning "[FAIL] Current version not detected (checked package.json, plugin Version header, theme Version header, and VERSION file)"
        else
            _gsr_error "[FAIL] Current version not detected (checked package.json, plugin Version header, theme Version header, and VERSION file)"
        fi
    fi

    # -- Last tag authority: every writable source must agree with it. Applies to
    # -- detection and to any release that assigns a version; --squash and --init
    # -- assign none, so they stay exempt (and are still safe: they do not tag).
    if [[ -n $LAST_TAG && $SQUASH_ONLY -eq 0 && $INIT -eq 0 ]]; then
        local drift_rc=0
        _gsr_check_version_drift "$LAST_TAG" || drift_rc=$?
        if (( drift_rc == 2 )); then
            _gsr_error "Malformed version value — fix it before releasing (--allow-version-drift does not accept malformed values)."
            DRIFT_FAILED=1
        elif (( drift_rc == 1 )); then
            if (( ALLOW_VERSION_DRIFT )); then
                _gsr_warning "Version drift accepted via --allow-version-drift; the release stays calculated from $LAST_TAG and rewrites every writable source."
            else
                _gsr_error "Version drift blocks this release: the last reachable tag ($LAST_TAG) assigns the version."
                printf '  Restore the premature version edits to %s, then re-run the release.\n' "${LAST_TAG#v}" >&2
                printf '  Or re-run with --allow-version-drift to repair every writable source from %s.\n' "$LAST_TAG" >&2
                DRIFT_FAILED=1
            fi
        fi
    fi

    if [[ $DETECT_ONLY -eq 1 ]]; then
        if [[ $DETECTION_FAILED -eq 0 && $DRIFT_FAILED -eq 0 ]]; then
            _gsr_success "All detections passed."
            return 0
        fi
        _gsr_warning "Some checks did not pass. Review the [FAIL] messages above and address them before running git-squash-release without -d."
        return 1
    fi

    if [[ $DETECTION_FAILED -ne 0 ]]; then
        if [[ $FORCE -eq 1 ]]; then
            _gsr_warning "Preflight checks failed but --force set, proceeding anyway..."
        else
            _gsr_error "Preflight checks failed. Run git-squash-release -d to inspect and fix failures."
            return 1
        fi
    fi

    # -- Drift is a hard stop: --force bypasses failed preflight checks, never the
    # -- drift invariant or a malformed version value.
    if (( DRIFT_FAILED )); then
        _gsr_error "Refusing to release with version drift (--force does not bypass it)."
        return 1
    fi

    # -- Hold the release marker for the whole mutating flow: divergence check,
    # -- prompts, version write, reset, tag, and push. Plan sessions refuse to
    # -- start or resume while it exists. --status and --detect never get here.
    SAVED_HEAD="$(git rev-parse HEAD 2>/dev/null || true)"
    if plans_dir=$(_gsr_plans_dir 2>/dev/null); then
        _gsr_release_marker_acquire "$plans_dir" || return 1
        trap '_gsr_release_marker_release' EXIT
        trap '_gsr_release_marker_on_signal' INT TERM HUP
    fi

    if ! _gsr_check_divergence "$SKIP_DIVERGENCE" "$MAIN_BRANCH"; then
        return 1
    fi

    # -- Initial release mode (no tags, confirmed): squash all history and tag 0.0.1 --
    if [[ $INITIAL_RELEASE -eq 1 ]]; then
        _gsr_loading2 "Initial release mode: squashing commit history and tagging 0.0.1"

        local ROOT_COMMIT ALL_COMMIT_MSGS RELEASE_TAG
        ROOT_COMMIT="$(git rev-list --max-parents=0 HEAD 2>/dev/null)"

        if [[ -z $ROOT_COMMIT ]]; then
            _gsr_error "Could not find root commit"
            return 1
        fi

        RELEASE_TAG="0.0.1"
        ALL_COMMIT_MSGS="$(_gsr_collect_commit_messages HEAD)"

        _gsr_loading "Root commit: $ROOT_COMMIT"
        _gsr_loading2 "All commits:"
        echo "$ALL_COMMIT_MSGS"
        echo ""

        _gsr_require_writable_source || return 1
        _gsr_recheck_mutation "$SAVED_HEAD" || return 1
        _gsr_update_all_versions "$RELEASE_TAG" || { _gsr_restore_saved_head; return 1; }
        _gsr_commit_release_version_bump "$RELEASE_TAG" || { _gsr_restore_saved_head; return 1; }

        if ! _gsr_recheck_mutation "${BUMP_HEAD:-$SAVED_HEAD}"; then
            _gsr_error "A commit landed during the release — re-run the release. The version bump is left in place."
            return 1
        fi

        _gsr_loading "Squashing all commits into one..."
        if ! git reset --soft "$ROOT_COMMIT"; then
            _gsr_error "Failed to soft-reset to the root commit"
            _gsr_restore_saved_head
            return 1
        fi

        if ! git commit -m "Release $RELEASE_TAG

$ALL_COMMIT_MSGS"; then
            _gsr_error "Failed to create the squashed release commit"
            _gsr_restore_after_reset
            return 1
        fi
        _gsr_success "Created squashed commit for initial release $RELEASE_TAG"

        _gsr_loading "Tagging commit as $RELEASE_TAG"
        if ! git tag -a "$RELEASE_TAG" -m "Release $RELEASE_TAG

$ALL_COMMIT_MSGS"; then
            _gsr_error "Failed to create tag $RELEASE_TAG"
            _gsr_restore_after_reset
            return 1
        fi
        _gsr_success "Tagged as $RELEASE_TAG"

        echo ""
        _gsr_push_prompt "$PUSH_MODE" "$ASSUME_YES" "$RELEASE_TAG" || return 1
        return 0
    fi

    # -- Init mode: squash entire commit history from the first commit --
    if [[ $INIT -eq 1 ]]; then
        _gsr_loading2 "Init mode: squashing entire commit history"

        local ROOT_COMMIT ALL_COMMIT_MSGS
        ROOT_COMMIT="$(git rev-list --max-parents=0 HEAD 2>/dev/null)"

        if [[ -z $ROOT_COMMIT ]]; then
            _gsr_error "Could not find root commit"
            return 1
        fi

        ALL_COMMIT_MSGS="$(_gsr_collect_commit_messages HEAD)"

        _gsr_loading "Root commit: $ROOT_COMMIT"
        _gsr_loading2 "All commits:"
        echo "$ALL_COMMIT_MSGS"
        echo ""

        if ! _gsr_confirm "Squash the entire history into one Initial commit (no tag)?"; then
            _gsr_warning "Cancelled."
            return 0
        fi

        _gsr_recheck_mutation "$SAVED_HEAD" || return 1

        _gsr_loading "Squashing all commits into one..."
        if ! git reset --soft "$ROOT_COMMIT"; then
            _gsr_error "Failed to soft-reset to the root commit"
            _gsr_restore_saved_head
            return 1
        fi

        if ! git commit -m "Initial commit

$ALL_COMMIT_MSGS"; then
            _gsr_error "Failed to create the squashed initial commit"
            _gsr_restore_after_reset
            return 1
        fi
        _gsr_success "Created squashed initial commit (entire history squashed)"
        return 0
    fi

    # Parse the last tag into major.minor.patch
    local _rest="${TAG_CLEAN#*.}"
    TAG_MAJOR="${TAG_CLEAN%%.*}"
    TAG_MINOR="${_rest%%.*}"
    TAG_PATCH="${TAG_CLEAN##*.}"

    # Calculate minor and major bump versions
    MINOR_VERSION="${TAG_MAJOR}.${TAG_MINOR}.$(( TAG_PATCH + 1 ))"
    MAJOR_VERSION="${TAG_MAJOR}.$(( TAG_MINOR + 1 )).0"

    # Preserve prefix if original tag had one (e.g. v1.2.3)
    if [[ $LAST_TAG == v* ]]; then
        TAG_PREFIX="v"
    fi

    MINOR_TAG="${TAG_PREFIX}${MINOR_VERSION}"
    MAJOR_TAG="${TAG_PREFIX}${MAJOR_VERSION}"

    # Get deduplicated commit messages since the last tag
    COMMIT_MSGS="$(_gsr_collect_commit_messages "$LAST_TAG..HEAD")"

    if [[ -z $COMMIT_MSGS ]]; then
        _gsr_error "No commits found since $LAST_TAG. Nothing to squash."
        return 1
    fi

    _gsr_loading "Last tag: $LAST_TAG ($LAST_TAG_COMMIT)"
    _gsr_loading2 "Commits since $LAST_TAG:"
    echo "$COMMIT_MSGS"
    echo ""

    if [[ $SQUASH_ONLY -eq 1 ]]; then
        # -- Squash-only mode: squash commits without tagging or version bump --
        _gsr_loading2 "Squash-only mode: no version bump or tagging"

        if ! _gsr_confirm "Squash commits since $LAST_TAG (no version change or tag)?"; then
            _gsr_warning "Cancelled."
            return 0
        fi

        _gsr_recheck_mutation "$SAVED_HEAD" || return 1

        _gsr_loading "Squashing all commits since $LAST_TAG into one..."
        if ! git reset --soft "$LAST_TAG_COMMIT"; then
            _gsr_error "Failed to soft-reset to $LAST_TAG"
            _gsr_restore_saved_head
            return 1
        fi

        if ! git commit -m "Squash commits since $LAST_TAG

$COMMIT_MSGS"; then
            _gsr_error "Failed to create the squashed commit"
            _gsr_restore_after_reset
            return 1
        fi
        _gsr_success "Created squashed commit (squash-only, no tag created)"
    else
        # -- Standard release flow: pick the version from the last tag and release --
        local RELEASE_TAG choice
        choice="$(_gsr_choose_bump "$BUMP" "$MINOR_TAG" "$MAJOR_TAG")"
        case "$choice" in
            minor)
                RELEASE_TAG="$MINOR_TAG"
                _gsr_success "Selected minor release: $RELEASE_TAG"
                ;;
            major)
                RELEASE_TAG="$MAJOR_TAG"
                _gsr_success "Selected major release: $RELEASE_TAG"
                ;;
            *)
                _gsr_warning "Cancelled."
                return 0
                ;;
        esac

        echo ""

        # -- Never squash onto a tag that already exists: the release commit would
        # -- be mis-versioned and the tag would point at the wrong squashed history.
        local existing_tag_commit
        if existing_tag_commit=$(git rev-list -n 1 "refs/tags/${RELEASE_TAG}" 2>/dev/null); then
            _gsr_error "Tag ${RELEASE_TAG} already exists (${existing_tag_commit:0:7}) — refusing to squash onto it"
            echo "  VERSION: ${CURRENT_VERSION:-none} (${CURRENT_VERSION_SOURCE:-none})" >&2
            echo "  Last reachable tag: ${LAST_TAG:-none}" >&2
            echo "  Choose a new version, or remove the stale tag after confirming it is not published:" >&2
            echo "    git tag -d ${RELEASE_TAG}" >&2
            return 2
        fi

        _gsr_require_writable_source || return 1

        if ! _gsr_confirm "Create release $RELEASE_TAG (squash commits since $LAST_TAG)?"; then
            _gsr_warning "Cancelled."
            return 0
        fi

        _gsr_recheck_mutation "$SAVED_HEAD" || return 1
        _gsr_update_all_versions "$RELEASE_TAG" || { _gsr_restore_saved_head; return 1; }
        _gsr_commit_release_version_bump "$RELEASE_TAG" || { _gsr_restore_saved_head; return 1; }

        _gsr_loading "Squashing all commits since $LAST_TAG into one..."
        _gsr_release_commit "$RELEASE_TAG" "$COMMIT_MSGS" || return 1

        echo ""

        _gsr_push_prompt "$PUSH_MODE" "$ASSUME_YES" "$RELEASE_TAG" || return 1
    fi

    return 0
}

main "$@"
