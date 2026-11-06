# Stack overview

How a request reaches a GridPane site, and how the box differs from a vanilla
Ubuntu LEMP server.

## Request flow

```
Visitor
  → Cloudflare / edge (optional; DNS proxy, CDN, WAF)
    → Web server: Nginx  OR  OpenLiteSpeed (lshttpd)
      → Page cache: FastCGI / Redis (Nginx)  OR  LSCache (OLS)
        → PHP: PHP-FPM pool (Nginx)  OR  LSAPI (OLS)
          → WordPress (runs as the site's system user)
            → MySQL/MariaDB (database)
            → Redis (object cache, optional)
```

Notes on the flow:

- The web server in use is per server, not per site. Confirm Nginx vs OLS before
  touching config; logs, include paths and service commands differ.
- Nginx page caching is FastCGI cache; the alternative page cache is Redis page
  cache. On OLS the page cache is **LSCache** (the LiteSpeed Cache plugin). Object
  caching is Redis and is separate from page caching. See the caching references
  in `gridpane-wordpress`.
- PHP runs differently: Nginx uses PHP-FPM pools; OLS uses **LSAPI** (PHP
  LiteSpeed SAPI), not PHP-FPM.
- Cloudflare in front changes what the origin sees: visitor IPs may appear as
  Cloudflare IPs until real-IP restoration is configured. See `gridpane-security`.
- A redirect loop is very often the Cloudflare SSL mode (e.g. Flexible) plus an
  origin redirect. See `gridpane-incident-triage`.

## Database engine and OS stack

The database is chosen per server at build time, not per site, and its version
follows the OS stack. The server-create API takes `database` as `percona` or
`mariadb` (`gridpane-api/references/endpoints.md`).

| Engine | Version by stack | Recognised as |
|---|---|---|
| MariaDB | 11.8 on Ubuntu 26.04; 10.11 on Ubuntu 22.04 and 24.04 | `mariadb118`, `mariadb` |
| Percona | 8.4 on current builds, an earlier release otherwise | `percona84`, `percona` |

Two consequences for an agent:

- **A feature on one stack can be absent on another.** Column types, collation
  families and index types differ between MariaDB 10.11, MariaDB 11.8 and
  Percona. Check the engine and version before assuming something exists; see
  `gridpane-server-diagnostics/references/mysql.md`.
- **Moving a site across engines is one-way.** GridPane's clone and restore paths
  refuse before touching the destination database when the destination cannot
  represent the source's data, and there is no in-place engine upgrade for
  MariaDB servers on 22.04/24.04: they stay on 10.11. Decide the destination
  before the first move, because moving back to 10.11 or Percona is refused
  rather than slow. See `gridpane-incident-triage`.

### Ubuntu 26.04 changed the migration rules

26.04 servers run Percona 8.4 or MariaDB 11.8. Percona 8.0 does not run there and
MariaDB 10.11 is not published for it, so every site arriving on a 26.04 server
lands on a newer database version than the one it left.

The engines are no longer interchangeable. Each now has default collations the
other does not fully recognise, so a dump taken from one can fail to load on the
other — and a cross-engine move (migration, clone, staging push or restore) is
much more likely to fail on 26.04 than on 22.04 or 24.04. Build the destination
with the **same database type as the source**: Percona to Percona, MariaDB to
MariaDB. The same rule covers the dump tools, because 26.04 ships a mydumper build
per database family (`gridpane-gp-cli/references/backups.md`).

- [Database Versions on Ubuntu 26.04: What Changes and Why](https://gridpane.com/kb/database-versions-on-ubuntu-26-04-what-changes-and-why/)
- [Migrating to Ubuntu 26.04: What You Need to Know](https://gridpane.com/kb/migrating-to-ubuntu-26-04-what-you-need-to-know/)

## OpenLiteSpeed specifics

- **Service:** `lshttpd` (Monit watches `/tmp/lshttpd/lshttpd.pid` and port 80).
  Restart with `gpols site {site.url}` / `gpols httpd`, or `systemctl restart lsws`.
- **Config is generated.** `/usr/local/lsws/conf/httpd_config.conf` and each
  site's `conf/vhosts/{site.url}/vhconf.conf` come from `gpols`; hand edits are
  overwritten. Add site rewrites to `/var/www/{site.url}/ols/rewrites.conf`.
- **PHP modes:** ProcessGroup (GridPane default), Worker (on-demand), Daemon
  (not offered on GridPane). See `ols.md`.
- **LSCache:** one cache directory is shared by all sites on the server, so an
  aggressive crawler on one large site can affect every site (and cause 503s).
- **Headers:** LSCache uses `HIT`/`MISS`, not the Nginx `X-Grid-*` headers.

## System users

Each site runs under its own system user, so a compromised plugin in one site
cannot read another site's files. Consequence for the agent: **run WP-CLI as the
site's system user**, using the wrapper:

```bash
# [READ] Run WP-CLI as the correct site system user.
gp wp example.com plugin list
```

Running raw `wp` as root against site files is wrong and can reset file
ownership and permissions. If you must use raw WP-CLI, switch to the site user
and run from the webroot; see `gridpane-wordpress`.

## Services and monitoring

- **Monit** watches services (Nginx or `lshttpd`, MySQL, PHP-FPM on Nginx, Redis)
  and restarts them when they falter. `/var/log/monit.log` records this. Monit
  also emits the memory and disk alerts GridPane sends.
- **Fail2ban** watches auth logs and bans abusive IPs. Jail `wordpress-extra`
  covers WordPress brute force. `/var/log/fail2ban.log` records events.
- **Redis** may be a single process (`redis-server`) or split into
  `redis-page` and `redis-object`. The correct `gp stack redis*` command depends
  on which your server has; check Monit first (`configure-redis` KB).

## How GridPane differs from a vanilla LEMP box

- **Managed config.** The Nginx vhost and PHP-FPM pool, or the OLS
  `httpd_config.conf`/`vhconf.conf`, plus `.user.ini`, are generated by GridPane
  and can be overwritten. Customise via the supported locations (`paths.md`).
- **`gp` CLI.** A large wrapper CLI sits on top of Nginx, PHP, MySQL, Redis,
  caching, WAFs and WP-CLI. Prefer it over hand edits.
- **Per-site pools and users.** Each site has its own system user and its own
  PHP pool: a PHP-FPM pool on Nginx, or an LSAPI process group on OLS.
- **Layered caches.** FastCGI or Redis page cache on Nginx, LSCache on OLS, plus
  optional Redis object cache, plus Cloudflare at the edge. A change to code can
  appear "not applied" because a cache layer served the old copy.
- **Hardening by default.** `/tmp` mounted `noexec` on Ubuntu 22.04+, UFW,
  Fail2ban, and optional WAFs (6G/7G/ModSecurity on Nginx; 7G/ModSecurity on
  OLS, which has no 6G).
- **GridPane-specific logs.** `/var/log/gridpane.log`, `/opt/gridpane/*.log` and
  per-site logs under `/var/www/{site.url}/logs/` have no vanilla equivalent.

## Unverified

- The exact default PHP-FPM process-manager mode and worker counts per pool on
  current GridPane Nginx stacks. Confirm on a real server before citing numbers.
- The exact default LSAPI mode and worker counts on OLS, and the OLS cache
  directory path (LSCache shares one directory across sites). See `ols.md`.
- The MariaDB 11.8 vector-search behaviour reported by GridPane staff on the
  community forum (2026-09-25): `VECTOR` columns and vector indexes on 11.8
  servers, one thread per table when restoring a database that has a vector
  index, the index rebuilt on every restore rather than copied, a 16 MB default
  vector index cache, and a `Clone Refused - DB Column Type` notification. The
  2026-10-14 `gpcli` snapshot contains no `VECTOR` handling at all, so none of it
  is confirmed in code. Recorded in `OPEN-QUESTIONS.md`.
