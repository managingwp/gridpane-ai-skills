#!/usr/bin/env bash
#
# install-kb-weekly-timer.sh - install the weekly KB report as a systemd user timer.
#
# Renders templates/systemd/gridpane-kb-weekly.{service,timer}.in for this
# checkout, writes them into the user unit directory, and reloads the user
# manager. It does not enable or start anything: enabling a recurring job is the
# operator's decision, and the command is printed instead.
#
# The rendered units carry nothing personal: the repository path comes from this
# checkout, the schedule from --calendar, and the mail recipient from the
# send-email transport's own configuration. An optional
# ~/.config/gridpane-kb-weekly/env file overrides settings per machine.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$ROOT/templates/systemd"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
CALENDAR="Mon *-*-* 08:00:00 UTC"

DRY_RUN=0
UNINSTALL=0

SERVICE="gridpane-kb-weekly.service"
TIMER="gridpane-kb-weekly.timer"

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Install (or remove) the weekly GridPane Knowledge Base report as a systemd user
timer. Prints the enable command instead of enabling the job.

Options:
  --calendar SPEC   Timer schedule (default: "Mon *-*-* 08:00:00 UTC")
  --unit-dir DIR    Target unit directory
                    (default: \${XDG_CONFIG_HOME:-\$HOME/.config}/systemd/user)
  --dry-run         Print the resolved paths and rendered units, write nothing
  --uninstall       Disable and remove the two units
  -h, --help        Show this help and exit

After installing:
  systemctl --user enable --now ${TIMER}

Mail settings live in the send-email transport, not in these units. To override
any setting per machine, use ~/.config/gridpane-kb-weekly/env.
EOF
}

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 2; }
have() { command -v "$1" >/dev/null 2>&1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --calendar) CALENDAR="${2:?--calendar needs a value}"; shift 2 ;;
        --calendar=*) CALENDAR="${1#--calendar=}"; shift ;;
        --unit-dir) UNIT_DIR="${2:?--unit-dir needs a value}"; shift 2 ;;
        --unit-dir=*) UNIT_DIR="${1#--unit-dir=}"; shift ;;
        --dry-run)  DRY_RUN=1; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

[[ -n "$CALENDAR" ]] || die "--calendar must not be empty"
have sed || die "sed is required"
[[ -d "$TEMPLATE_DIR" ]] || die "templates not found: $TEMPLATE_DIR"

# sed replacement text: escape the delimiter and both special characters.
sed_escape() {
    printf '%s' "$1" | sed -e 's/[\\&#]/\\&/g'
}

render() {
    sed -e "s#@REPO_ROOT@#$(sed_escape "$ROOT")#g" \
        -e "s#@CALENDAR@#$(sed_escape "$CALENDAR")#g" "$1"
}

reload_units() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        return 0
    fi
    if ! have systemctl; then
        log "warning: systemctl not found; reload the user manager by hand"
        return 0
    fi
    systemctl --user daemon-reload \
        || log "warning: 'systemctl --user daemon-reload' failed; reload the user manager by hand"
}

if [[ "$UNINSTALL" -eq 1 ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf 'would disable and remove: %s/%s\n' "$UNIT_DIR" "$TIMER"
        printf 'would remove: %s/%s\n' "$UNIT_DIR" "$SERVICE"
        exit 0
    fi
    if have systemctl; then
        systemctl --user disable --now "$TIMER" 2>/dev/null \
            || log "note: the timer was not enabled, or the user manager is not running"
    fi
    for name in "$TIMER" "$SERVICE"; do
        if [[ -f "$UNIT_DIR/$name" ]]; then
            rm -f "$UNIT_DIR/$name"
            printf 'removed: %s\n' "$UNIT_DIR/$name"
        fi
    done
    reload_units
    exit 0
fi

for name in "$SERVICE" "$TIMER"; do
    [[ -f "$TEMPLATE_DIR/$name.in" ]] || die "missing template: $TEMPLATE_DIR/$name.in"
done

if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'repo:      %s\n' "$ROOT"
    printf 'unit dir:  %s\n' "$UNIT_DIR"
    printf 'calendar:  %s\n' "$CALENDAR"
    printf '\n--- %s ---\n' "$SERVICE"
    render "$TEMPLATE_DIR/$SERVICE.in"
    printf '\n--- %s ---\n' "$TIMER"
    render "$TEMPLATE_DIR/$TIMER.in"
    printf '\nwould write: %s/%s\n' "$UNIT_DIR" "$SERVICE"
    printf 'would write: %s/%s\n' "$UNIT_DIR" "$TIMER"
    exit 0
fi

mkdir -p "$UNIT_DIR"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"

for name in "$SERVICE" "$TIMER"; do
    target="$UNIT_DIR/$name"
    if [[ -f "$target" ]]; then
        cp "$target" "$target.bak-$stamp"
        printf 'backed up: %s.bak-%s\n' "$target" "$stamp"
    fi
    render "$TEMPLATE_DIR/$name.in" > "$target.tmp"
    chmod 644 "$target.tmp"
    mv "$target.tmp" "$target"
    printf 'wrote: %s\n' "$target"
done

reload_units

printf '\nEnable the weekly run with:\n  systemctl --user enable --now %s\n' "$TIMER"
printf 'Check it with:\n  systemctl --user list-timers %s\n' "$TIMER"
