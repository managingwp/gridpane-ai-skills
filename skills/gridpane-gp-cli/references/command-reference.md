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

## Nginx stack

`gp stack nginx {group} {flag} …` writes Nginx configuration. Without a `{site.url}`
the flag is server-wide; `limits`, `fastcgi` and `proxy` also accept `-site-*`
flags with `{site.url}` last, which is how one site is tuned without touching the
others. Full flag list per group: Configure Nginx (see Sources in `SKILL.md`).

| Label | Group | Flags |
|---|---|---|
| [WRITE] | `worker` | `-connections {int}`, `-rlimit-nofile {int}` |
| [WRITE] | `server-name` | `-in-redirect on\|off`, `-hash-bucket-size {int}` |
| [WRITE] | `limits` | `-client-body-buffer-size`, `-client-body-timeout`, `-client-header-buffer-size`, `-client-header-timeout`, `-keepalive-requests`, `-keepalive-timeout`, `-large-client-header-buffers {qty} {size}`, `-req-zone-one {store.mb} {req/s}`, `-req-zone-wp {store.mb} {req/s}`, `-reset-timedout-connection`, `-send-timeout`, `-types-hash-max-size` |
| [WRITE] | `limits` (per site) | `-site-zone-one-burst {n} {site.url}`, `-site-zone-wp-burst {n} {site.url}`, `-site-max-body-size {MB} {site.url}` |
| [WRITE] | `open-file-cache` | `-max {elements} -inactive {timeout}`, `-errors on\|off`, `-min-uses {int}`, `-valid {int}` |
| [WRITE] | `fastcgi` | `-buffering`, `-buffers {qty} {size}`, `-buffer-size`, `-busy-buffers-size`, `-cache-background-update`, `-max-cache-size`, `-cache-revalidate`, `-connect-timeout`, `-keep-connections`, `-read-timeout`, `-send-timeout`, `-site-cache-valid {seconds} {site.url}` |
| [WRITE] | `proxy` | the same flags as `fastcgi`, including `-site-cache-valid {seconds} {site.url}` |
| [WRITE] | `redis` | `-site-cache-valid {seconds} {site.url}` |
| [WRITE] | `geoip` | `-on {account.id}:{license.key}`, `-off`, `-update {CC}:{yes\|no},…`, `-remove {CC},…` |

### Per-site page-cache TTL

Each page-cache type has its own `-site-cache-valid`, and it only writes the
directive for that cache type:

| Cache type | Command | Directive and file | Default |
|---|---|---|---|
| Redis | `gp stack nginx redis -site-cache-valid {seconds} {site.url}` | `redis2_query expire $key $cache_ttl` in `/etc/nginx/common/{site.url}-wp-redis.conf`, `-proxy-http-rediscache.conf`, `-proxy-https-rediscache.conf` | `2592000` (30 days) |
| FastCGI | `gp stack nginx fastcgi -site-cache-valid {seconds} {site.url}` | `fastcgi_cache_valid` in `/etc/nginx/common/{site.url}-fcgi-cache-var.conf` | `1` |
| Proxy | `gp stack nginx proxy -site-cache-valid {seconds} {site.url}` | `proxy_cache_valid` in `/etc/nginx/common/{site.url}-proxy-cache-var.conf` | `1` |

Choose the form that matches the site's recorded `cache-type`
(`/var/www/{site.url}/logs/{site.url}.env`); the `redis` form on a FastCGI site
does not change what that site serves. Passing the default value changes nothing
except the config rewrite.

- Effect: the TTL before a cached 200 response is refetched — one site only.
- Rollback: re-run with the previous value (or the default above).
- Verify: `gp ngx -t`, then the TTL key in the site env and a cache header as in
  `gridpane-wordpress/references/caching.md`. Reload with `gp ngx -reload` if the
  site still serves the old TTL.

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

Read `references/backups.md` when a backup succeeds without a revision, when the
panel's backup buttons spin, when local backups are configured but never run, or
before taking a one-off local backup. It covers the entry points and their tags,
the toggles and schedules, the disk threshold, the two lock files, the shared
task-spooler queue, the completion callback, and the log files.

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
