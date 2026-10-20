# Per-site state: `/var/www/{site.url}/logs/{site.url}.env`

GridPane records per-site state as `key:value` in this file. It is the per-site
counterpart to `/root/gridenv`: where `/root/gridenv` describes the *server*,
this file describes *one site* — its cache method, PHP version, pool size, WAF
and cron settings, and site identity.

Read it to answer "what is configured for this site" without guessing from the
panel. It is read-only for you and it contains credentials: never edit it, and
never print secret values into a transcript, ticket or commit.

Read this alongside `gridpane-wordpress/references/caching.md` (cache method),
`gridpane-server-diagnostics/references/php-fpm.md` (pool sizing) and
`gridpane-security/references/waf.md` (WAF state).

## Reading it (all [READ])

```bash
# [READ] One non-secret key, without dumping the whole file.
grep -E '^(cache-type|redis-object-cache|php-ver|cron):' /var/www/{site.url}/logs/{site.url}.env
```

Do not `cat` the whole file in a shared session: it holds database, WordPress
and Redis credentials.

## Cache keys (the authoritative per-site answer)

| Key | Meaning | Observed value |
|---|---|---|
| `cache-type` | Page-cache method recorded for the site | `redis` |
| `ngx-redis-cache-valid` | Redis page-cache TTL, seconds | `2592000` |
| `nginx-caching-ttl` | Cache TTL, seconds | `2592000` |
| `redis-object-cache` | Redis object cache on/off | `true` |
| `redis-db`, `redis-page-db` | Redis database index for the site | `3` |
| `wp-redis-prefix`, `ocp-redis-prefix` | Redis key prefixes (site-identifying) | hash |
| `nginx-helper-redis-prefix-hash` | Nginx Helper cache prefix hash | hash |
| `nginx-helper-redis-password` | **Secret. Never print.** | — |

`cache-type` is the definitive server-side statement of the page cache
(`lib/site.sh:1410-1418`, `15010-15052`):

| Value | Meaning | Expected header |
|---|---|---|
| `redis` | Nginx Redis page cache | `X-Grid-SRCache-Fetch` |
| `fastcgi` | Nginx FastCGI page cache | `X-Grid-Cache` |
| `off` | Nginx page caching disabled (any other value is coerced to `off`) | neither |

OpenLiteSpeed sites write the LSCache state instead: `redis-page` (page +
object), `page-only`, `redis-only`, or `off` (`lib/site.sh:15018-15028`).

This is why `caching.md` tells you to check both header families: a
`cache-type:redis` site looks "uncached" if you only look for `X-Grid-Cache`.

## Other key groups

| Group | Keys |
|---|---|
| Site identity | `primary-domain`, `site-id`, `primary-domain-id`, `sys-user`, `route`, `nginx-config`, `ssl`, `suspend`, `http-auth`, `multisite`, `dns-management`, `smtp` |
| Database | `db-name`, `db-user` (password is secret) |
| PHP | `php-ver`, `pm`, `pm.max_children`, `pm.start_servers`, `pm.min_spare_servers`, `pm.max_spare_servers`, `pm.max_requests`, `pm.process_idle_timeout`, `memory_limit`, `max_execution_time`, `max_input_time`, `max_input_vars`, `post_max_size`, `upload_max_filesize`, `max_file_uploads`, `default_socket_timeout`, `date.timezone`, `session.gc_maxlifetime`, `session.cookie_lifetime`, `short_open_tag`, `php_slowlog`, `php_slowlog_timeout`, `php_slowlog_trace_depth` |
| Cron | `cron`, `cron-freq`, `cron-fuzziness` |
| WAF / hardening | `waf`, `modsec-paranoia`, `modsec-threshold`, `modsec-*`, `7G-*`, `disable-xmlrpc`, `block-wp-*`, `block-install.php`, `gridpane-*-plugin`, `wp-fail2ban` |
| Backups | `backup-max-disk-usage`, `backup-schedule-local*`, `prune-schedule-*`, `last-backup-refresh-local` |
| Feature flags | `secure-debug`, `brotli`, `http2-push`, `kill-emoji`, `elasticpress`, `auto-updates`, `wsod-fix` |

## Secret keys — never echo

`db-pass`, `wp-user`, `wp-email`, `wp-pass`, `application-token`,
`nginx-helper-redis-password`, and the Redis prefix/hash values. Anonymise all of
these before sharing a copy.

## Related files in the same directory

| File | Holds |
|---|---|
| `backups.env` | Backup state (`Remote-Backups`, `Local-Backups`, last manual/auto runs) |
| `disable.*.env` | Per-feature toggles, each a bare `true`/`false` |
| `gp-sitecron.on`, `gp-sitecron.fuzziness` | GP-Cron interval and fuzziness |
| `wpadmin_id.env` | WP admin user id used by GridPane tools |
| `{site.url}-build.log` | Site build steps |
| `*.log`, `*.log.1` | Rotated site logs (see `gridpane-core/references/paths.md`) |

## Gotchas

- **This is per site, not per server.** A server can run Redis page caching and
  still have a FastCGI site; read this file, not just `/root/gridenv`.
- **`cache-type` and the response header must agree.** If they do not, the site
  may be mid-switch or bypassed; read the skip header.
- **Do not edit.** GridPane rewrites this file; change settings via `gp` or the
  panel.
- **The file name is the primary domain** (`{site.url}.env`), even when the
  site has additional domains.

## Unverified

- The complete key set: new keys appear as GridPane adds features.

## Sources

- WP-Cron and GP-Cron — https://gridpane.com/kb/wp-cron-and-gridpanes-gp-cron-updated/
  (documents the per-site `{site.url}.env` file and the `cron:true` key).
- Maintainer-supplied capture of a site's `logs/` directory, 2026-10-09 (cache
  and PHP keys verified; secrets redacted).

Last verified: 2026-10-09
