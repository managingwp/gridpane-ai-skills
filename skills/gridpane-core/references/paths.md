# Paths

Verified locations on a GridPane server. `{site.url}` is the site's primary
domain, e.g. `example.com`. All paths assume root (or sudo) over SSH unless a
path explicitly says otherwise.

See `sources.md` for the Knowledge Base page behind each group.

## Site files

| Purpose | Path |
|---|---|
| Webroot (WordPress files) | `/var/www/{site.url}/htdocs` |
| Site root | `/var/www/{site.url}` |
| `wp-config.php` (GridPane-managed; one level **above** webroot) | `/var/www/{site.url}/wp-config.php` |
| Build-time backup of `wp-config.php` | `/opt/gridpane/site-configs` |
| Per-site PHP overrides (written by `gp`/panel) | `/var/www/{site.url}/htdocs/.user.ini` |
| Per-site log directory | `/var/www/{site.url}/logs/` |
| Per-site Nginx includes (safe to add) | `/var/www/{site.url}/nginx/*-main-context.conf` |

To edit your own `wp-config`-level PHP constants, use the custom user-configs
file rather than editing `wp-config.php`. See the migrations/cloning KB article
in `sources.md`.

## Nginx configuration

| Purpose | Path |
|---|---|
| Site virtual server (managed; symlinked into `sites-enabled`) | `/etc/nginx/sites-available/{site.url}` |
| Per-site common configs (managed) | `/etc/nginx/common/{site.url}-{config-name}.conf` |
| Server-wide `main`/`http` context includes (safe to add) | `/etc/nginx/extra.d/*-main-context.conf` |
| Server-wide `http` context include | `/etc/nginx/extra.d/http-context.conf` |
| Safe copy destination GridPane will not overwrite | `/etc/nginx/extra.d/_custom/` |
| Per-site includes (safe to add) | `/var/www/{site.url}/nginx/*-main-context.conf` |

The active Nginx include lines are:

```nginx
include /etc/nginx/extra.d/*main-context.conf;
include /var/www/site.url/nginx/*-main-context.conf;
```

## OpenLiteSpeed (OLS) configuration

| Purpose | Path |
|---|---|
| Server config / IP deny list | `/usr/local/lsws/conf/ip_deny.conf` |
| Web server error log | `/usr/local/lsws/logs/error.log` |
| Web server stderr log (useful for 503s) | `/usr/local/lsws/logs/stderr.log` |

Restart OLS and regenerate its config with `gpols httpd`.

## PHP

| Purpose | Path |
|---|---|
| Per-site PHP-FPM pool (managed) | `/etc/php/{php.version}/fpm/pool.d/{site.url}.conf` |
| PHP-FPM service log | `/var/log/php/{php.version}/fpm.log` |
| PHP slow log | `/var/log/{site.url}{version-no-dot}.log.slow` |

Example slow-log path for `example.com` on PHP 7.3: `/var/log/example.com73.log.slow`.

## Databases and cache

| Purpose | Path |
|---|---|
| MySQL/MariaDB data directory | `/var/lib/mysql` |
| MySQL/MariaDB service and error log | `/var/log/mysql/error.log` |
| Redis config | `/etc/redis/redis.conf` |
| Redis log | `/var/log/redis/redis-server.log` |

## Site logs (per site)

Under `/var/www/{site.url}/logs/`:

| Log | Answers |
|---|---|
| `debug.log` | WP debug output, when Secure WP Debug is on |
| `gridpane-general.log` | Changes made in the site customizer |
| `domains.log` | Domain add-on and primary-domain swaps |
| `manual-backups.log` | Manually triggered backups and failures |
| `sso.log` | Single sign-on events and magic links |
| `ssl-provision.log` | SSL provisioning attempts and failures |
| `staging.log` | Live→Staging and Staging→Live pushes |
| `6g.log`, `7g.log` | 6G/7G WAF block events |

## Web access and error logs

| Server | Access log | Error log |
|---|---|---|
| Nginx | `/var/log/nginx/{site.url}.access.log` | `/var/log/nginx/{site.url}.error.log` |
| OpenLiteSpeed | `/var/log/ols/{site.url}.access.log` | `/var/log/ols/{site.url}.error.log` |

ModSecurity events are written to the web server's site **error** log.

## Server logs and GridPane tooling

| Purpose | Path |
|---|---|
| GridPane command log (what ran, when) | `/var/log/gridpane.log` |
| Server health check results | `/var/log/health-check.log` |
| Authentication events / brute force | `/var/log/php/auth.log` |
| Fail2ban events | `/var/log/fail2ban.log` |
| Monit (service restarts, alerts) | `/var/log/monit.log` |
| GridPane clone log | `/opt/gridpane/gpclone.log` |
| Automated backups monitoring | `/opt/gridpane/backups.monitoring.log` |
| Certbot renewals (webroot SSLs) | `/opt/gridpane/certbot.monitoring.log` |
| ACME renewals (DNS API SSLs) | `/opt/gridpane/acme.monitoring.log` |
| Git errors | `/opt/gridpane/git.error.log` |
| UFW firewall log | `/var/log/ufw_log` |
| System log | `/var/log/syslog` |
| System temporary directory (noexec on 22.04+) | `/tmp` |

## Files GridPane regenerates — never hand-edit

Editing any of these directly will be undone the next time GridPane regenerates
the file (a change in the control panel, a `gp` command, a clone or a restore):

- `/etc/nginx/sites-available/{site.url}` (the site virtual server)
- `/etc/nginx/common/{site.url}-*.conf`
- `/etc/php/{php.version}/fpm/pool.d/{site.url}.conf`
- `/var/www/{site.url}/htdocs/.user.ini`
- `/var/www/{site.url}/wp-config.php`

**Where to customise instead:** the include locations in this file —
`/etc/nginx/extra.d/*-main-context.conf`, `/etc/nginx/extra.d/http-context.conf`,
`/var/www/{site.url}/nginx/*-main-context.conf` — and the custom user-configs
file for PHP constants. Copy server-wide includes into
`/etc/nginx/extra.d/_custom/` so GridPane does not overwrite them.

## /tmp hardening (Ubuntu 22.04 and later)

GridPane mounts `/tmp` as `noexec` by default so a compromised site cannot run
binaries from it. `/tmp` is cleared on reboot.

```bash
# [READ] Check whether /tmp is mounted noexec (look for "noexec").
findmnt -no OPTIONS /tmp
```

```bash
# [WRITE] Unlock /tmp so a third-party app can execute there (weakens hardening).
# Blast radius: whole server. Backup: none (it is a mount option). Rollback:
# re-run with "enable". Confirm before running.
gp server -tmp-noexec disable
```

```bash
# [WRITE] Re-lock /tmp as noexec.
gp server -tmp-noexec enable
```

## Unverified

- Exact MySQL **slow query** log filename: the logs KB page gives
  `/var/log/mysql/error.log` for the slow log in one place but shows
  `cat /var/log/mysql/slow.log` elsewhere. Confirm on a real server before
  relying on either path. Tracked in `OPEN-QUESTIONS.md`.
- Whether MariaDB (rather than MySQL) is the default engine on current
  GridPane stacks, and how that changes `systemctl` unit names.
