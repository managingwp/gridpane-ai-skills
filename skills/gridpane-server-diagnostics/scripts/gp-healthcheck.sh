#!/usr/bin/env bash
#
# gp-healthcheck.sh - read-only health snapshot of a GridPane-managed server.
#
# Collects: load average, memory and swap, root filesystem disk and inode use,
# service states, per-pool PHP-FPM worker counts, established MySQL connections,
# Redis memory use, the GridPane server environment (/root/gridenv) and recent
# 5xx counts from the web server access logs.
#
# This script only reads. It never changes server state.
#
# Usage: gp-healthcheck.sh [--json] [--site DOMAIN] [--help]

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
OUTPUT_JSON=0
SITE=""
JSON_SERVICES=""
JSON_POOLS=""
JSON_5XX=""

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [--json] [--site DOMAIN] [--help]

Read-only snapshot of a GridPane server: load, memory/swap, disk and inodes,
service states, PHP-FPM pool worker counts, MySQL connections, Redis memory, the
GridPane environment (/root/gridenv) and recent 5xx counts from the web server
access logs.

Options:
  --json          Emit machine-readable JSON to stdout instead of text.
  --site DOMAIN   Restrict per-site sections (PHP-FPM pools, access logs) to one
                  domain, and report that site's page-cache method from its
                  per-site env (cache-type) or Nginx config. Without it, every
                  site is reported.
  -h, --help      Show this help and exit.

This script only reads state.
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }

json_escape() {
    # Escape backslashes and double quotes for safe embedding in JSON strings.
    printf '%s' "${1:-}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# --- argument parsing -------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) OUTPUT_JSON=1; shift ;;
        --site)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                printf 'error: --site requires a domain\n' >&2
                exit 2
            fi
            SITE="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *)
            printf 'error: unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# --- collectors -------------------------------------------------------------

get_load() {
    # /proc/loadavg: "0.10 0.20 0.30 1/234 5678"
    awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null || printf 'unknown'
}

meminfo_kb() {
    awk -v key="$1" '$1 == key {print $2; found=1} END {if (!found) print 0}' /proc/meminfo 2>/dev/null || printf '0'
}

svc_state() {
    local svc="$1"
    if have systemctl; then
        local state
        state="$(systemctl is-active "$svc" 2>/dev/null || true)"
        printf '%s' "${state:-inactive}"
    else
        printf 'unknown'
    fi
}

list_php_versions() {
    local d
    for d in /etc/php/*/fpm; do
        [[ -d "$d" ]] || continue
        basename "$(dirname "$d")"
    done
}

php_pool_counts() {
    # "php-fpm: pool example.com" -> pool name is the third field.
    # Only accept a plausible pool name (domain-like), so unrelated php-fpm
    # processes on a non-GridPane host do not pollute the output.
    ps -eo args 2>/dev/null \
        | awk '/php-fpm: pool/ && $3 ~ /^[A-Za-z0-9.-]+$/ {print $3}' \
        | sort | uniq -c | sort -nr || true
}

mysql_connections() {
    if have ss; then
        ss -Htn state established 2>/dev/null \
            | awk '$4 ~ /:3306$/ || $5 ~ /:3306$/' | wc -l | tr -d ' '
    else
        printf 'unknown'
    fi
}

redis_memory() {
    if have redis-cli; then
        redis-cli -h 127.0.0.1 info memory 2>/dev/null \
            | awk -F: '/^used_memory_human/ {print $2}' | tr -d '\r' || true
    fi
}

# Read a single non-secret key from a /root/gridenv env file. Prints nothing on
# a miss. Only fixed, known-safe keys are ever requested.
gridenv_value() {
    local file="$1" key="$2"
    [[ -r "$file" ]] || return 0
    grep -m1 "^${key}:" "$file" 2>/dev/null | cut -d: -f2- || true
}

gridenv_active_site_count() {
    local f="/root/gridenv/active-sites.env"
    [[ -r "$f" ]] || { printf '0'; return 0; }
    awk '/^:/ {c++} END {print c+0}' "$f" 2>/dev/null || printf '0'
}

gridenv_flag() {
    # "true" if a /root/gridenv/<file> exists (feature configured on this server).
    local f="$1"
    if [[ -r "$f" ]]; then printf 'true'; else printf 'false'; fi
}

site_cache_method() {
    # Determine a site's page cache. Read-only.
    # Prefer the per-site env's recorded cache-type; fall back to Nginx config.
    # Prints: redis | fastcgi | none | unknown.
    local site="$1" f hits envfile
    if [[ -z "$site" ]]; then printf 'unknown'; return 0; fi
    envfile="/var/www/${site}/logs/${site}.env"
    if [[ -r "$envfile" ]]; then
        f="$(grep -m1 '^cache-type:' "$envfile" 2>/dev/null | cut -d: -f2- | tr -d '[:space:]' || true)"
        if [[ -n "$f" ]]; then printf '%s' "$f"; return 0; fi
    fi
    local paths=("/etc/nginx/sites-available/${site}")
    for f in /etc/nginx/common/"${site}"-*.conf; do
        [[ -e "$f" ]] && paths+=("$f")
    done
    hits="$(grep -RhoE 'srcache[a-z_]*|redis2_query' "${paths[@]}" 2>/dev/null | sort -u || true)"
    if [[ -n "$hits" ]]; then printf 'redis'; return 0; fi
    hits="$(grep -RhoE 'fastcgi_cache[a-z_]*' "${paths[@]}" 2>/dev/null | sort -u || true)"
    if [[ -n "$hits" ]]; then printf 'fastcgi'; return 0; fi
    printf 'none'
}

site_object_cache() {
    # The site's recorded Redis object-cache state. Read-only.
    local site="$1" envfile
    [[ -n "$site" ]] || return 0
    envfile="/var/www/${site}/logs/${site}.env"
    [[ -r "$envfile" ]] || return 0
    grep -m1 '^redis-object-cache:' "$envfile" 2>/dev/null | cut -d: -f2- | tr -d '[:space:]' || true
}

collect_5xx() {
    # Best effort: field 9 is the status in the standard combined format.
    local pattern site
    if [[ -n "$SITE" ]]; then
        pattern="/var/log/nginx/${SITE}.access.log /var/log/ols/${SITE}.access.log"
    else
        pattern="/var/log/nginx/*access.log /var/log/ols/*access.log"
    fi
    for f in $pattern; do
        [[ -f "$f" ]] || continue
        site="$(basename "$f" | sed -E 's/\.access\.log.*$//')"
        awk -v site="$site" '$9 ~ /^5/ {c++} END {if (c) printf "%s %d\n", site, c}' "$f"
    done | sort -k2 -nr
}

# --- gather -----------------------------------------------------------------

LOAD="$(get_load)"
MEM_TOTAL_KB="$(meminfo_kb MemTotal:)"
MEM_AVAIL_KB="$(meminfo_kb MemAvailable:)"
SWAP_TOTAL_KB="$(meminfo_kb SwapTotal:)"
SWAP_FREE_KB="$(meminfo_kb SwapFree:)"
MEM_TOTAL_MB=$(( MEM_TOTAL_KB / 1024 ))
MEM_AVAIL_MB=$(( MEM_AVAIL_KB / 1024 ))
SWAP_TOTAL_MB=$(( SWAP_TOTAL_KB / 1024 ))
SWAP_FREE_MB=$(( SWAP_FREE_KB / 1024 ))

DISK_ROW="$(df -Pk / 2>/dev/null | awk 'NR==2 {print $2" "$3" "$4" "$5}' || printf 'unknown')"
DISK_USED_KB="$(awk '{print $2}' <<<"$DISK_ROW")"
DISK_AVAIL_KB="$(awk '{print $3}' <<<"$DISK_ROW")"
DISK_PCT="$(awk '{print $4}' <<<"$DISK_ROW")"
DISK_USED_MB=$(( ${DISK_USED_KB:-0} / 1024 ))
DISK_AVAIL_MB=$(( ${DISK_AVAIL_KB:-0} / 1024 ))

INODE_ROW="$(df -Pi / 2>/dev/null | awk 'NR==2 {print $2" "$3" "$5}' || printf 'unknown')"
INODE_PCT="$(awk '{print $3}' <<<"$INODE_ROW")"

SERVICE_LIST=""
for svc in nginx mysql mariadb redis-server redis-page redis-object lshttpd; do
    state="$(svc_state "$svc")"
    SERVICE_LIST+="${svc}=${state} "
    JSON_SERVICES+="{\"name\":\"$(json_escape "$svc")\",\"state\":\"$(json_escape "$state")\"},"
done
while IFS= read -r ver; do
    [[ -n "$ver" ]] || continue
    svc="php${ver}-fpm"
    state="$(svc_state "$svc")"
    SERVICE_LIST+="${svc}=${state} "
    JSON_SERVICES+="{\"name\":\"$(json_escape "$svc")\",\"state\":\"$(json_escape "$state")\"},"
done < <(list_php_versions)

POOL_REPORT="$(php_pool_counts)"
while read -r count pool; do
    [[ -n "${pool:-}" ]] || continue
    JSON_POOLS+="{\"pool\":\"$(json_escape "$pool")\",\"workers\":${count}},"
done <<<"$POOL_REPORT"

MYSQL_CONNS="$(mysql_connections)"
REDIS_MEM="$(redis_memory)"

GP_ENV_DIR="/root/gridenv"
GP_SERVER_VERSION="$(gridenv_value "$GP_ENV_DIR/promethean.env" server-version)"
GP_SERVER_BUILD="$(gridenv_value "$GP_ENV_DIR/promethean.env" server-build)"
GP_WEBSERVER="$(gridenv_value "$GP_ENV_DIR/promethean.env" webserver)"
GP_ACTIVE_SITES="$(gridenv_active_site_count)"
GP_REDIS_PAGE="$(gridenv_flag "$GP_ENV_DIR/redis-page.env")"
GP_REDIS_OBJECT="$(gridenv_flag "$GP_ENV_DIR/redis-object.env")"
GP_SITE_CACHE="$(site_cache_method "$SITE")"
GP_SITE_OBJECT="$(site_object_cache "$SITE")"

FIVEXX_REPORT="$(collect_5xx)"
while read -r site count; do
    [[ -n "${count:-}" ]] || continue
    JSON_5XX+="{\"site\":\"$(json_escape "$site")\",\"count\":${count}},"
done <<<"$FIVEXX_REPORT"

# --- output -----------------------------------------------------------------

if [[ "$OUTPUT_JSON" -eq 1 ]]; then
    cat <<EOF
{
  "hostname": "$(json_escape "$(hostname)")",
  "site_filter": "$(json_escape "$SITE")",
  "load": "$(json_escape "$LOAD")",
  "memory_mb": {"total": ${MEM_TOTAL_MB}, "available": ${MEM_AVAIL_MB}},
  "swap_mb": {"total": ${SWAP_TOTAL_MB}, "free": ${SWAP_FREE_MB}},
  "disk_root": {"used_mb": ${DISK_USED_MB}, "available_mb": ${DISK_AVAIL_MB}, "used_pct": "$(json_escape "$DISK_PCT")"},
  "inodes_root": {"used_pct": "$(json_escape "$INODE_PCT")"},
  "services": [${JSON_SERVICES%,}],
  "php_pools": [${JSON_POOLS%,}],
  "mysql_established_connections": "${MYSQL_CONNS}",
  "redis_used_memory": "$(json_escape "$REDIS_MEM")",
  "gridpane_env": {
    "server_version": "$(json_escape "$GP_SERVER_VERSION")",
    "server_build": "$(json_escape "$GP_SERVER_BUILD")",
    "webserver": "$(json_escape "$GP_WEBSERVER")",
    "active_sites": ${GP_ACTIVE_SITES},
    "redis_page_configured": ${GP_REDIS_PAGE},
    "redis_object_configured": ${GP_REDIS_OBJECT},
    "site_cache_method": "$(json_escape "$GP_SITE_CACHE")",
    "site_object_cache": "$(json_escape "$GP_SITE_OBJECT")"
  },
  "http_5xx_counts": [${JSON_5XX%,}]
}
EOF
    exit 0
fi

printf 'GridPane health check on %s\n' "$(hostname)"
printf 'Site filter: %s\n' "${SITE:-<all sites>}"
printf '\n'
printf 'Load average (1m 5m 15m): %s\n' "$LOAD"
printf 'Memory: %s MB available of %s MB\n' "$MEM_AVAIL_MB" "$MEM_TOTAL_MB"
printf 'Swap:   %s MB free of %s MB\n' "$SWAP_FREE_MB" "$SWAP_TOTAL_MB"
printf 'Disk /: %s MB used, %s MB free (%s)\n' "$DISK_USED_MB" "$DISK_AVAIL_MB" "$DISK_PCT"
printf 'Inodes /: %s used\n' "$INODE_PCT"
printf '\nServices:\n'
for entry in $SERVICE_LIST; do
    printf '  %s\n' "$entry"
done
printf '\nPHP-FPM workers per pool:\n'
if [[ -n "$POOL_REPORT" ]]; then
    while read -r count pool; do
        [[ -n "${pool:-}" ]] || continue
        printf '  %5s  %s\n' "$count" "$pool"
    done <<<"$POOL_REPORT"
else
    printf '  (none found)\n'
fi
printf '\nMySQL established connections: %s\n' "$MYSQL_CONNS"
printf 'Redis used memory: %s\n' "${REDIS_MEM:-unavailable}"
printf '\nGridPane environment (/root/gridenv):\n'
if [[ -r /root/gridenv ]]; then
    printf '  server: %s %s (webserver: %s)\n' \
        "${GP_SERVER_VERSION:-unknown}" "${GP_SERVER_BUILD:-unknown}" "${GP_WEBSERVER:-unknown}"
    printf '  active sites on this server: %s\n' "$GP_ACTIVE_SITES"
    printf '  redis page cache configured: %s\n' "$GP_REDIS_PAGE"
    printf '  redis object cache configured: %s\n' "$GP_REDIS_OBJECT"
else
    printf '  (/root/gridenv not present or not readable)\n'
fi
if [[ -n "$SITE" ]]; then
    printf '  site page cache method (%s): %s\n' "$SITE" "$GP_SITE_CACHE"
    printf '  site redis object cache (%s): %s\n' "$SITE" "${GP_SITE_OBJECT:-unknown}"
fi
printf '\nHTTP 5xx responses by site (from access logs):\n'
if [[ -n "$FIVEXX_REPORT" ]]; then
    while read -r site count; do
        [[ -n "${count:-}" ]] || continue
        printf '  %6s  %s\n' "$count" "$site"
    done <<<"$FIVEXX_REPORT"
else
    printf '  (none found, or access logs not readable)\n'
fi
