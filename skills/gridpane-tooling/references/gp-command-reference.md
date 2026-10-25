# `gp` command reference (dispatcher view)

The complete top-level `gp` command tree as the dispatcher actually implements
it, extracted from `tmp/gpcli/usr/local/bin/gp`. This is the **developer** view:
it includes internal and undocumented commands (e.g. `audit`, `conf`,
`function-run`) that the KB does not cover.

For flag-level detail on the user-facing commands (caching, WAF, backups, PHP
settings, …), use `gridpane-gp-cli/references/command-reference.md`. This file
maps each top-level command to the module function it calls.

Legend: **[READ]** inspect, **[WRITE]** reversible change, **[DESTRUCTIVE]** hard
to reverse, **[?]** verify on a real server before treating as a given.

## Top-level commands

| Command (aliases) | Dispatches to | Purpose | Label |
|---|---|---|---|
| `site` (`-site`) | `site::*` | Site lifecycle and settings | varies |
| `wp` (`-wp`) | `site::gridpane_wpcli` | WP-CLI as the site system user (`all-sites` supported) | varies |
| `user` (`-user`) | `user::main` | System users | [WRITE] |
| `switch` (`-switch`) | `user::main -switch` | Switch a site's system user | [WRITE] |
| `backup` (`-backup`) | `gpbup::main` | Backups (legacy + Duplicacy) | [WRITE]/[DESTRUCTIVE] |
| `clone` (`-clone`) | `clone::main` | Clone a site | [WRITE] |
| `restore` (`-restore`) | `restore::main` | Restore a site | [DESTRUCTIVE] |
| `dns` (`-dns`) | `dns::main` | DNS records | [WRITE] |
| `failsync` (`-failsync`) | `failsync::main` | Failover sync | [WRITE] |
| `cloudflare` (`-cloudflare`) | `gridpane::cloudflare::{enable,disable}` | Cloudflare integration | [WRITE] |
| `scan` (`-scan`) | `scan::main` | Malware/vulnerability scanning | [WRITE]/[READ] |
| `fix` (`-fix`) | `fix::*`, `gridpane::cache::*` | Repairs and cache clearing | [WRITE] |
| `stack` (`-stack`) | `stack::*`, `php::configure`, `installphp` | Stack component configuration | [WRITE] |
| `server` (`-server`) | `server::*`, `tools::*`, `gridpane::check::*` | Server-wide settings | varies |
| `monit` (`-monit`) | `monit::main` | Monit configuration | [WRITE] |
| `monitor` (`-monitor`) | `monitor::main` | Monit-triggered notifications | [WRITE] |
| `audit` (`-audit`) | `workers::audit::*` | Read-only site/system-user inventory audit | [READ] |
| `conf` (`-conf`) | `gridpane::conf_*`, nginx checks | Read/write config; nginx/php/wp checks | varies |
| `update` (`-update`) | `gpupdate` | Run the updater | [WRITE] |
| `worker` (`-worker`) | `worker::main` | Scheduled workers (fifteen-min/hourly/daily/weekly) | [WRITE] |
| `loop` (`-loop`) | `loop::main` | Looping helper | [?] |
| `git` | `gpgit` | Git integration | [WRITE] |
| `function-test` / `function-run` | the named shell function | **Internal:** invoke a function directly | varies |
| `callback` (`-callback`) | `gridpane::callback::app` | Call back to the GridPane app API | [WRITE] |
| `mysql` (`-mysql`) | `services::mysql_services` | MySQL/MariaDB service control | [WRITE] |
| `ngx` (`-ngx`, `nginx`) | `services::nginx_services` | Nginx service control | [WRITE] |
| `ols` (`-ols`) | `gpols::main` | OpenLiteSpeed | [WRITE] |
| `php` (`-php`) | `services::php_services` | PHP-FPM per version | [WRITE] |
| `redis` (`-redis`, `redis-server`, `redis-page`, `redis-object`) | `services::redis_services` | Redis service control | [WRITE] |
| `postgresql` (`-postgresql`, `psql`) | `postgresql::services` | PostgreSQL (non-default stacks) | [WRITE] |

Unknown top-level commands exit `187`.

## Subcommands the KB does not cover

These are implemented in the dispatcher and worth knowing as a tool author.

### `audit` — read-only inventory

| Command | Purpose | Label |
|---|---|---|
| `gp audit active-sites` (alias `site-owner-inventory`) | Classify the sites on disk; read-only | [READ] |
| `gp audit system-users` | System-user ↔ site ownership audit; read-only | [READ] |

Enrolment is suspended; `add`/`remove` operands are refused with exit `2`
(`gp:189-241`). The audit captures and returns the worker's status
(`gp:218-223`).

### `conf` — read/write config

| Command | Purpose | Label |
|---|---|---|
| `gp conf read \| write \| delete` | Config read/write/delete via `gridpane::conf_*` | varies |
| `gp conf global {key}` | Read a server global (`gridpane::get_server_global`) | [READ] |
| `gp conf ngx type-check \| cache-check \| show \| generate` | Nginx config checks/generation | varies |
| `gp conf php ver-check` | Site PHP version check | [READ] |
| `gp conf wp update-host` | Update a site's `wp-config` host | [WRITE] |

### `server` — server-wide settings

| Command | Purpose | Label |
|---|---|---|
| `gp server check-uuid` | Verify the server UUID | [READ] |
| `gp server check-reboot-required` | Reboot-required check | [READ] |
| `gp server health-check` | Read the health-check log (`logs::health_check_read`) | [READ] |
| `gp server kill-process …` | Kill a process | [DESTRUCTIVE] |
| `gp server provider-update` | Provider update hook | [WRITE] |
| `gp server sync-system-settings` / `sync-stack` / `sync-http-auth` | Sync settings from the app | [WRITE] |
| `gp server tmp-noexec enable\|disable` | `/tmp` noexec (Ubuntu 22.04+ only) | [WRITE] |
| `gp server update-borg` | Borg quota | [WRITE] |
| `gp server update-monit` | Regenerate monit config | [WRITE] |
| `gp server update-timezone` / `update-unattended-upgrades` / `update-hostname` / `update-token` / `update-server-key` | Server settings | [WRITE] |
| `gp server update-failover-configuration` / `update-failover*` / `remove-failover-remnants` | Failover config | [WRITE] |
| `gp server update-user-account` | Re-validate the account | [READ]/[WRITE] |

### `stack` — component configuration

| Command | Purpose | Label |
|---|---|---|
| `gp stack nginx …` | Nginx directives (`stack::configure_nginx`) | [WRITE] |
| `gp stack php …` / `php opcache` / `php install` | PHP settings, OPcache, install (`installphp`) | [WRITE] |
| `gp stack mysql …` | MySQL/MariaDB settings | [WRITE] |
| `gp stack redis \| redis-page \| redis-object …` | Redis settings | [WRITE] |
| `gp stack ols …` | OpenLiteSpeed settings | [WRITE] |
| `gp stack geoip …` | GeoIP config | [WRITE] |
| `gp stack maldet …` | Maldet config | [WRITE] |
| `gp stack elasticsearch …` | Elasticsearch config | [WRITE] |
| `gp stack *-fail2ban-jail` | Enable/disable a Fail2ban jail | [WRITE] |
| `gp stack *upgrades*` | Unattended-upgrades config | [WRITE] |

### `fix` — repairs and cache

| Command | Purpose | Label |
|---|---|---|
| `gp fix cached [{site.url}]` | Clear caches (all, or one site) | [WRITE] |
| `gp fix cached page-cache \| object-cache …` | Clear a specific cache | [WRITE] |
| `gp fix perms {site.url}` | Reset file permissions | [WRITE] |
| `gp fix binds …` | Fix DNS binds | [WRITE] |
| `gp fix creds wp …` | Update WP credentials | [WRITE] |
| `gp fix force-update {site.url}` | Force a site update | [WRITE] |
| `gp fix pass {site.url}` | Fix a site password | [WRITE] |

### `function-run` / `function-test` — internal

`gp function-run <name> [args…]` calls the named shell function directly (it
must already be sourced from `lib/`). `function-test` is the same with a printed
header. Useful for debugging a module; dangerous in the wrong hands, since it can
call any function, including mutating ones.

Worked example: `gp -function-run 'gpbup::callback::manual_backup_status 1
{site} local'` posts the backup completion callback that re-enables the panel's
backup buttons — see `gridpane-gp-cli/references/backups.md` for when that is
legitimate. The `callback` area is the same transport used directly:
`gp callback /backups/backup -- site_url=… status=failed service=local`.

## Wrappers

| Wrapper | Equivalent |
|---|---|
| `gpsite` | `gp site …` |
| `gpuser` | `gp user …` |
| `gpswitch` | `gp switch …` |
| `gpclone` | `gp clone …` |
| `gprestore` | `gp restore …` |
| `gpscan` | `gp scan …` |
| `gpmonit` | `gp monit …` |
| `gpmonitor` | `gp monitor …` |
| `gpfix` | `gp fix …` |
| `gpols` | `gp ols …` |
| `gpbup` / `gpbup2` | `gp backup …` |
| `gpworker` | `gp worker -fifteen-min …` |
| `gphourlyworker` / `gpdailyworker` / `gpweeklyworker` | `gp worker -hourly/-daily/-weekly …` |

`gpupdate`, `gpcheck` and `gpgit` are standalone scripts, not wrappers.

## Site flags (from the dispatcher)

`gp site {site.url} …` accepts a large flag set. These are the meaningful
user-facing flags, grouped, as they appear in the dispatcher's `site` case
(`gp:601-2454`). Most also accept an un-prefixed alias. Flag-level usage and
units are in `gridpane-gp-cli/references/command-reference.md`.

| Group | Flags |
|---|---|
| Domains / routing | `-add-domain`, `-delete-domain`, `-add-301-domain`, `-create-domain-wildcard`, `-route-domain-root`, `-route-domain-www`, `-route-domain-off`, `-swap-primary-domain`, `-set-nginx-default`, `-set-openlitespeed-default` |
| SSL | `-domain-ssl-on/-off`, `-domain-wildcard-ssl-on/-off`, `-primary-ssl-on/-off`, `-primary-wildcard-ssl-on/-off`, `-wildcard-ssl-on/-off`, `-auto-ssl`/`-enable-auto-ssl`/`-disable-auto-ssl`, `-renew-ssl`, `-renew-domain-ssl`, `-dns-creds`, `-update-dns-creds`, `-delete-dns-creds` |
| Caching | `-fastcgi-caching`, `-redis-caching`, `-redis-cache`, `-cache-off`, `-redis-object-caching`, `-cache-valid`, `-fcgi-cache-valid`, `-redis-cache-valid`, `-proxy-cache-valid`, `-enable-object-cache-pro`, `-disable-object-cache-pro`, `-update-object-cache-pro` |
| WAF / hardening | `-modsec-on/-off`, `-modsec-settings`, `-block-*`/`-unblock-*` (`wp-content.php`, `wp-comments-post.php`, `wp-links-opml.php`, `wp-trackbacks.php`, `install.php`, `upgrade.php`, `wpscan-agent`), `-disable-xmlrpc`/`-enable-xmlrpc`, `-disable-username-enum`/`-enable-username-enum`, `-disable-wp-version`/`-enable-wp-version`, `-disable-rss`/`-enable-rss`, `-disable-emoji`/`-enable-emoji`, `-maldet-scan` |
| Headers / transport | `-http-auth`/`-http-auth-off`, `-csp-header-on/-off`, `-clickjacking-protection-on/-off`, `-brotli-on/-off`, `-http2-push-preload-on/-off` |
| PHP | `-switch-php`, `-update-php`, `-php-settings`, `-set-chroot-php`, `-phpver` |
| Cron | `-gpcron-on`, `-gpcron-off` |
| Backups | `-enable-local-backups`, `-enable-remote-backups`, `-purge-backups`, `-purge-backups-and-gridpane-logs`, `-purge-gridpane-logs`, `-backups-time` |
| Staging / clone | `-staging`, `-staging-no-bup`, `-staging-no-db`, `-staging-only-db`, `-pre-clone-check`, `-clone-check` |
| Users | `-add-wp-users`, `-rotate-wp-user-passwords`, `-wp-user-passwords`, `-create-new-user` |
| Fail2ban | `-enable-wp-fail2ban`/`-disable-wp-fail2ban`, `-configure-wp-fail2ban` |
| Debug | `-wp-debug-on/-off`, `-wsod-on/-off` |
| Site state | `-suspend`, `-unsuspend` |
| Sync (all-sites) | `-sync-php-settings`, `-sync-6g-settings`, `-sync-7g-settings`, `-sync-modsec-settings`, `-sync-wpf2b-settings`, `-sync-nginx-cache-settings`, `-sync-object-cache-settings`, `-sync-nginx-settings`, `-sync-access-settings`, `-sync-additional-security-settings`, `-sync-fortress-settings`, `-sync-from-app` |

### Reconciliation

On 2026-10-16 every `-flag` documented in
`gridpane-gp-cli/references/command-reference.md` (117 of them) was found in the
dispatcher, so the KB reference is current for the flags it covers. The
dispatcher also contains many internal aliases not documented in the KB; use the
KB reference for user-facing usage and this table for the dispatcher's set.

## Unverified

- Exact accepted units and value ranges for every flag; confirm from
  `gp … --help` on a real server. The flag *set* is reconciled against the KB
  reference above; the value ranges are not.
- The `[?]` labels above (`loop`, parts of `conf`) — confirm whether they change
  state.
- Whether `scan` still fronts Patchstack scanning; the snapshot has no separate
  `patchstack` top-level label.

## Sources

- `tmp/gpcli/usr/local/bin/gp` (dispatch table, subcommands, exit codes).
- `tmp/gpcli/usr/local/bin/gpupdate` (update dispatch).
- `tmp/gpcli/README.md` (areas and wrappers).
- `gridpane-gp-cli/references/command-reference.md` (flag reconciliation).

Last verified: 2026-10-16
