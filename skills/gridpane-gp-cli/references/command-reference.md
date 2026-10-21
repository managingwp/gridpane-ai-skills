# gp command reference

Verified `gp` commands, grouped by area. Every row carries a label. This is
extracted from the GP-CLI Quick Reference and the dedicated KB articles, plus
the deployed script snapshot for the internal entry points the KB does not
document (see `sources.md`). When in doubt, confirm flags with `gp … --help` on
the server before running.

For the complete dispatcher view — every top-level command including internal
ones such as `audit`, `conf` and `function-run`, mapped to the functions they
call — see `gridpane-tooling/references/gp-command-reference.md`.

Legend: **[READ]** inspect, **[WRITE]** reversible change, **[DESTRUCTIVE]** hard
to reverse.

Every **[WRITE]** and **[DESTRUCTIVE]** command here follows the protocol in
`gridpane-core/references/safety.md`: show the command, effect, blast radius,
backup and rollback, and wait for confirmation before running. Rollbacks in
general: toggles/settings are re-run with the previous value or the `-off`/reset
variant; service reload/restart has no data change; managed config is regenerated
by `gp` so there is nothing to hand-restore. **[DESTRUCTIVE]** commands (site
deletion, database drop, backup purge, staging overwrite) additionally require the
user to name the action and a verified backup to exist.

## Services

| Label | Command | Notes |
|---|---|---|
| [WRITE] | `gp ngx -start` / `-stop` / `-reload` / `-restart` | Nginx service. Prefer `-reload`. |
| [READ] | `gp ngx -status` / `gp ngx -t` | Status; config test. |
| [WRITE] | `gp php {version} -start` / `-stop` / `-reload` / `-restart` | PHP-FPM for one version. |
| [WRITE] | `gp mysql -start` / `-stop` / `-reload` / `-restart` | MySQL/MariaDB (server-wide). |
| [WRITE] | `gp redis -start` / `-stop` / `-reload` / `-restart` | Redis service. |
| [WRITE] | `gpols httpd` | Regenerate OLS config and restart OLS. |

## Site basics

| Label | Command | Notes |
|---|---|---|
| [WRITE] | `gp site {site.url} -switch-php {version}` | Change the site's PHP version. |
| [WRITE] | `gp site {site.url} -route-domain-www` | Force `www`. |
| [WRITE] | `gp site {site.url} -route-domain-root` | Force root domain. |
| [WRITE] | `gp site {site.url} -route-domain-off` | Disable routing. |
| [WRITE] | `gp site {site.url} -suspend` / `-unsuspend` | Suspend/resume a site. |
| [WRITE] | `gp site {site.url} -suspend -use-server-custom` / `-use-site-custom` | Suspend with a custom holding page. |
| [WRITE] | `gp site {site.url} -set-nginx-default` | Make this the default vhost. |
| [WRITE] | `gp site default -set-nginx-default` | Reset to the secure GridPane default vhost. |
| [WRITE] | `gp fix perms {site.url}` | Reset file permissions. |
| [READ] | `gp site {site.url} -disable-xmlrpc` etc. | See Nginx hardening below. |

## Nginx hardening (per site)

| Label | Command |
|---|---|
| [WRITE] | `gp site {site.url} -disable-xmlrpc` / `-enable-xmlrpc` |
| [WRITE] | `gp site {site.url} -block-wp-content.php` / `-unblock-wp-content.php` |
| [WRITE] | `gp site {site.url} -disable-concatenate-load-scripts` / `-enable-concatenate-load-scripts` |
| [WRITE] | `gp site {site.url} -block-wp-comments-post.php` / `-unblock-…` |
| [WRITE] | `gp site {site.url} -block-wp-links-opml.php` / `-unblock-…` |
| [WRITE] | `gp site {site.url} -block-wp-trackbacks.php` / `-unblock-…` |
| [WRITE] | `gp site {site.url} -block-upgrade.php` / `-unblock-…` |
| [WRITE] | `gp site {site.url} -block-install.php` / `-unblock-…` |

## PHP settings

Per-version stack defaults:

| Label | Command |
|---|---|
| [WRITE] | `gp stack php {version} -max-exec-time {int}` |
| [WRITE] | `gp stack php {version} -mem-limit {int}` |
| [WRITE] | `gp stack php {version} -upload-max-filesize {int}` |
| [WRITE] | `gp stack php {version} -post-max-size {int}` |
| [WRITE] | `gp stack php {version} -max-input-vars {int}` |
| [WRITE] | `gp stack php {version} -date-timezone {tz}` |
| [WRITE] | `gp stack php {version} -opcache-enable` / `-opcache-disable` |
| [WRITE] | `gp stack php {version} -opcache-memory {int}` |

Per-site overrides (positional `{site.url}` last):

| Label | Command |
|---|---|
| [WRITE] | `gp stack php -site-max-exec-time {int} {site.url}` |
| [WRITE] | `gp stack php -site-mem-limit {int} {site.url}` |
| [WRITE] | `gp stack php -site-upload-max-filesize {int} {site.url}` |
| [WRITE] | `gp stack php -site-post-max-size {int} {site.url}` |
| [WRITE] | `gp stack php -site-pm {value} {site.url}` |
| [WRITE] | `gp stack php -site-pm-max-children {value} {site.url}` |
| [WRITE] | `gp stack php -site-slowlog true|false {site.url}` |

## MySQL stack

| Label | Command |
|---|---|
| [WRITE] | `gp stack mysql -max-connections {int}` |
| [WRITE] | `gp stack mysql -innodb-buffer-pool-size {value}` |
| [WRITE] | `gp stack mysql -innodb-buffer-pool-instances {value}` |
| [WRITE] | `gp stack mysql -slow-query-log {value}` |
| [WRITE] | `gp stack mysql -long-query-time {value}` |
| [READ] | `gp mysql login root` (interactive) |
| [READ] | `gp mysql get-pass root` (prints a secret — never log it) |

## Redis stack

| Label | Command |
|---|---|
| [WRITE] | `gp stack redis -max-memory {MB}` |
| [WRITE] | `gp stack redis -maxmemory-policy {policy} [{MB}]` |
| [WRITE] | `gp stack redis -enable-persistence` / `-disable-persistence` |
| [WRITE] | `gp stack redis -reset` |
| [WRITE] | `gp stack redis-page -maxmemory {MB}` (split-Redis servers) |
| [WRITE] | `gp stack redis-object -maxmemory {MB}` (split-Redis servers) |

## Caching

| Label | Command | Notes |
|---|---|---|
| [WRITE] | `gp site {site.url} -fastcgi-cache -ttl {seconds}` | Enable Nginx FastCGI page cache. Default TTL 1s. |
| [WRITE] | `gp site {site.url} -redis-cache -ttl {seconds}` | Enable Redis page cache. |
| [WRITE] | `gp site {site.url} -cache-off` | Disable page caching. |
| [WRITE] | `gp site {site.url} -redis-object-caching on` / `off` | Redis object cache. |
| [WRITE] | `gp fix cached {site.url}` | Clear all caches, one site. |
| [WRITE] | `gp fix cached` | Clear all caches, **every site on the server**. |

## WAFs

| Label | Command |
|---|---|
| [WRITE] | `gp site {site.url} -6g-on` / `-6g-off` |
| [WRITE] | `gp site {site.url} -7g-on` / `-7g-off` |
| [WRITE] | `gp site {site.url} 7g -bad-bots on` / `off` (and bad-query-string, bad-referer, bad-request, bad-methods) |
| [WRITE] | `gp site {site.url} -modsec-on` / `-modsec-off` |
| [WRITE] | `gp site {site.url} -modsec -paranoia-level {1-4}` |
| [WRITE] | `gp site {site.url} -modsec -anomaly-threshold {int}` |

## Fail2ban

| Label | Command |
|---|---|
| [WRITE] | `gp site {site.url} -enable-wp-fail2ban` / `-disable-wp-fail2ban` |
| [WRITE] | `gp site {site.url} -configure-wp-fail2ban -block-user-enumeration` / `-unblock-user-enumeration` |
| [WRITE] | `gp site {site.url} -configure-wp-fail2ban -default` |
| [WRITE] | `gp site {site.url} -configure-wp-fail2ban -guard-comments` / `-unguard-comments` |

## Backups

| Label | Command | Notes |
|---|---|---|
| [WRITE] | `gpbup2 {site.url} -local-single-site` | Trigger one local v2 backup. |
| [WRITE] | `gpbup {site.url} -local-single-site` / `-remote-single-site {storage}` | Manual backup, tagged `<epoch>-manual`. |
| [WRITE] | `gpbup {site.url} -run-single-site {storage}` | Cron interface: queue one scheduled-form backup (async). |
| [WRITE] | `gpbup {site.url} -local-bup-on` / `-local-bup-off` | Toggle automated local backups; `-on` also writes the local schedule cron and syncs the panel. |
| [WRITE] | `gpbup {site.url} -remote-bup-on` / `-remote-bup-off` | Toggle automated remote backups. |
| [WRITE] | `gpbup all-sites -remote-bup-on` / `-remote-bup-off` | **All sites.** |
| [DESTRUCTIVE] | `gpbup {site.url} -purge {storage} "{from}" "{to}"` | Delete backups in a date range. |
| [WRITE] | `gpbup -update-gridpane-backups-system` | Update the backup system. |
| [WRITE] | `gpbup {site.url} -set-backup-schedule …` | Set a schedule. |

`{storage}` is `local` or a configured remote (`aws-s3`, `backblaze`, `dropbox`,
`wasabi`). The site argument must match the `/var/www/{site}` directory name
exactly; `www.` and `staging.` forms address a different site or fail.

### How the backup entry points differ

`gpbup` and `gpbup2` are one-line wrappers: `set -- "backup" "$@"` then source
`/usr/local/bin/gp`, so every call lands in `gpbup::main`.

- `-run-single-site {storage}` is what GridPane writes into
  `/etc/cron.d/backup-{interval}-{storage}-{site}`, so it is the scheduled-run
  path. It does not back anything up itself: it queues
  `gp backup {site} -single-site {storage}` in the task-spooler queue on socket
  `/tmp/ts-socket-backups.<uid>` (installed on demand, one job at a time) and
  returns at once, printing the task id. A plain `tsp -l` looks empty because it
  uses the default socket; use
  `TS_SOCKET=/tmp/ts-socket-backups.0 tsp -l` to watch it.
- `-single-site {storage}` is that queued executor. It runs in the foreground
  and logs to `/opt/gridpane/active.backups.monitoring.log`.

Both end in `gpbup::backup {site} {storage}`, which for `local`:

1. requires `Local-Backups:ON` in `/var/www/{site}/logs/backups.env`; when local
   backups are off for the site it backs up **nothing** and still exits 0, so a
   zero exit here is not proof a backup exists. A skipped run is easy to spot: it
   finishes in about a second and `active.backups.monitoring.log` stops at
   `Local backups are NOT enabled for {site}.` with no `Backup of {site} Done!`
   line;
2. waits for the per-site backup lock rather than skipping the run (manual
   backups do not wait); if the lock is not obtained, the `-single-site` arm
   returns 1 instead of 0, so a queued job is not recorded as a success;
3. refuses when free space on `/opt/gridpane/backups/duplications` minus the
   database dump would fall below `backup-max-disk-usage`% of the filesystem
   (default 10%);
4. dumps the database, then runs `duplicacy backup -t gp-automated`, so the
   revision lists as an **automatic** local backup, and this path does **not**
   prune.

Prefer `-local-single-site` when you want a backup an operator can identify: it
is tagged `<epoch>-manual`, takes the lock without waiting, does not require the
`Local-Backups:ON` toggle, checks the disk threshold after the dump, and
refreshes the available-backups list so the UI shows the new revision. All of
these need root, because the Duplicacy password comes from
`/root/gridcreds/gridpane.uuid`.

## WP debug, cron, compression, auth, CSP

| Label | Command |
|---|---|
| [WRITE] | `gp site {site.url} -wp-debug-on` / `-wp-debug-off` |
| [WRITE] | `gp site {site.url} -gpcron-on {minutes}` / `-gpcron-off` |
| [WRITE] | `gp site {site.url} -brotli-on` / `-brotli-off` |
| [WRITE] | `gp site {site.url} -http-auth` / `-http-auth-off` |
| [WRITE] | `gp site {site.url} -csp-header-on` / `-csp-header-off` |

## WP-CLI wrapper

| Label | Command | Notes |
|---|---|---|
| varies | `gp wp {site.url} {wp.cli.command} {args…}` | Runs as the site system user. `--ssh` is unsupported; use raw WP-CLI. |

## Sync settings (server-wide)

| Label | Command |
|---|---|
| [WRITE] | `gp site all-sites sync-php-settings` |
| [WRITE] | `gp site all-sites sync-6g-settings` |
| [WRITE] | `gp site all-sites sync-7g-settings` |
| [WRITE] | `gp site all-sites sync-modsec-settings` |
| [WRITE] | `gp site all-sites sync-wpf2b-settings` |
| [WRITE] | `gp site all-sites sync-nginx-cache-settings` |
| [WRITE] | `gp site all-sites sync-object-cache-settings` |

These apply to **every site on the server**.

## Server toggles

| Label | Command |
|---|---|
| [READ] | `gp server -tmp-noexec` (status) |
| [WRITE] | `gp server -tmp-noexec enable` / `disable` |

## Monit

| Label | Command |
|---|---|
| [WRITE] | `gpmonit redis -mem-high-mb {int}` |
| [WRITE] | `gpmonit redis-page -mem-high-mb {int}` (split Redis) |
| [WRITE] | `gpmonit redis-object -mem-high-mb {int}` (split Redis) |

## Unverified

- Exact accepted units and value ranges per flag; confirm from `--help` output.
- Whether `gpupdate` is purely a refresh or can change state; confirm with
  `gpupdate --help` before treating it as [READ].
