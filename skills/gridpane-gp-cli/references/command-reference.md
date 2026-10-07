# gp command reference

Verified `gp` commands, grouped by area. Every row carries a label. This is
extracted from the GP-CLI Quick Reference and the dedicated KB articles
(see `sources.md`). When in doubt, confirm flags with `gp … --help` on the
server before running.

Legend: **[READ]** inspect, **[WRITE]** reversible change, **[DESTRUCTIVE]** hard
to reverse.

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
| [WRITE] | `gpbup {site.url} -remote-bup-on` / `-remote-bup-off` | Toggle automated remote backups. |
| [WRITE] | `gpbup all-sites -remote-bup-on` / `-remote-bup-off` | **All sites.** |
| [DESTRUCTIVE] | `gpbup {site.url} -purge {storage} "{from}" "{to}"` | Delete backups in a date range. |
| [WRITE] | `gpbup -update-gridpane-backups-system` | Update the backup system. |
| [WRITE] | `gpbup {site.url} -set-backup-schedule …` | Set a schedule. |

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
