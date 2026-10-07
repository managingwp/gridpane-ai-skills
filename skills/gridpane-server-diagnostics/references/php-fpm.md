# PHP-FPM on GridPane

How per-site PHP-FPM pools work, how to spot `max_children` saturation, and how
to read the PHP slow log.

## The per-site pool model

Each site has its own PHP-FPM pool for its own PHP version, under its own system
user. The pool file is managed by GridPane:

```
/etc/php/{php.version}/fpm/pool.d/{site.url}.conf
```

Never hand-edit that file: `gp`/the panel regenerates it. Change pool settings
with `gp stack php -site-*` instead (below). This differs from a vanilla LEMP box
where several sites often share one pool.

The site's PHP version can be changed with:

```
gp site {site.url} -switch-php {version}
```

## Reading pool saturation

PHP processes appear in `ps` as `php-fpm: master process` and
`php-fpm: pool {site.url}` workers. Count workers per pool:

```bash
# [READ] Worker count per pool (field after "php-fpm: pool" is the site).
ps -eo args | awk '/php-fpm: pool/ {print $3}' | sort | uniq -c | sort -nr
```

The clearest sign of saturation is in the pool's service log
(`/var/log/php/{php.version}/fpm.log`). When every worker is busy and requests
queue, PHP-FPM logs a warning like:

```
WARNING: [pool example.com] server reached pm.max_children setting (5), consider raising it
```

If you see that line repeatedly and in step with the symptom, the pool is
worker-starved. Confirm before changing anything:

- Is it one pool or all pools? One pool is a single-site problem.
- Is the box RAM- or CPU-bound at the same time? Raising `max_children` on a
  RAM-starved box makes things worse, not better.

```bash
# [READ] Look for max_children warnings in the PHP-FPM log for a version.
grep -i 'max_children' /var/log/php/8.1/fpm.log | tail -n 20
```

## Changing pool settings ([WRITE])

Per-site process manager and worker settings. The value and the site URL are
positional; the command reloads PHP for that site.

```bash
# [WRITE] Example: raise the pool's max children for one site.
# Effect: allows more simultaneous PHP requests for example.com.
# Blast radius: site example.com only (but it uses more RAM).
# Backup: the pool file is regenerated; note the current value first with
#         `grep pm.max_children /etc/php/8.1/fpm/pool.d/example.com.conf`.
# Rollback: re-run with the previous value.
# Confirm before running.
gp stack php -site-pm-max-children 10 example.com
```

Related commands (all [WRITE], per site):

| Setting | Command |
|---|---|
| Process manager mode | `gp stack php -site-pm {value} {site.url}` |
| Max children | `gp stack php -site-pm-max-children {value} {site.url}` |
| Start servers | `gp stack php -site-pm-start-servers {value} {site.url}` |
| Min spare servers | `gp stack php -site-pm-min-spare-servers {value} {site.url}` |
| Max spare servers | `gp stack php -site-pm-max-spare-servers {value} {site.url}` |
| Max requests per child | `gp stack php -site-pm-max-requests {value} {site.url}` |
| Idle timeout | `gp stack php -site-pm-process-idle-timeout {value} {site.url}` |

Some `gp` commands reload PHP automatically. When chaining several changes, pass
the documented `-no-reload` flag so you reload once (see `gridpane-core`
`references/gp-conventions.md`).

## The PHP slow log

Only available on **Nginx** servers. It records a backtrace for any request that
runs longer than `request_slowlog_timeout` seconds, which is how you find the
plugin or query behind 502/504s and high load.

### Enable (Nginx)

```bash
# [WRITE] Turn the slow log on for one site.
# Effect: PHP writes slow-request backtraces for example.com.
# Blast radius: site example.com only.
# Backup: none (a pool setting; the pool file is regenerated).
# Rollback: `gp stack php -site-slowlog false example.com`.
# Confirm before running.
gp stack php -site-slowlog true example.com
```

```bash
# [WRITE] Log requests slower than 5 seconds (value is in seconds).
gp stack php -site-slowlog-timeout 5 example.com
```

```bash
# [WRITE] Record 15 frames of backtrace.
gp stack php -site-slowlog-trace-depth 15 example.com
```

### Read it

The log lives in `/var/log` and is named `{site.url}{version-without-dot}.log.slow`:

```bash
# [READ] View the slow log for a site on PHP 8.1.
cat /var/log/example.com81.log.slow
```

A block looks like:

```
[09-Mar-2022 22:25:08] [pool example.com81] pid 20039
script_filename = /var/www/example.com/htdocs/wp-cron.php
[0x00007fe04e814520] [INCLUDE_OR_EVAL]() /var/www/example.com/htdocs/wp-content/plugins/wordfence/wordfence.php:115
[0x00007fe04e814440] [INCLUDE_OR_EVAL]() /var/www/example.com/htdocs/wp-settings.php:418
```

The `script_filename` line is the requested script; the first line of the
backtrace is the function running when the timeout was exceeded — usually the
offending code. The slow log captures the script but not the URI, so match it to
the access log if you need the URL.

### Three common causes

1. `wp-cron.php` — usually harmless background work, but old sites with piled-up
   cron events can overload. Check with the WP Crontrol plugin.
2. `mysqli_query` — inefficient or unindexed database queries. Cross-check with
   the MySQL slow log (`references/mysql.md`).
3. `curl_exec` — the site calling an external service that is slow or rate
   limiting. Confirm the call is necessary.

### Disable

```bash
# [WRITE] Turn the slow log back off once done.
# Effect: stops slow-request logging for example.com.
# Blast radius: site example.com only.
# Backup: none. Rollback: re-enable if you need it again.
# Confirm before running.
gp stack php -site-slowlog false example.com
```

## Gotchas

- The slow log is Nginx-only; it is not available on OpenLiteSpeed.
- Always turn the slow log off after debugging; leaving it on adds overhead and
  fills disk.
- Raising `max_children` is a trade: more concurrency versus more RAM. On a
  swapping box, fix RAM or find the slow request first.

## Sources

- Using the PHP Slow Log — https://gridpane.com/kb/using-the-php-slow-log/
- Configure PHP — https://gridpane.com/kb/configure-php/
- GP-CLI Quick Reference — https://gridpane.com/kb/gp-cli-quick-reference/
- PHP Workers guide — https://gridpane.com/blog/php-workers-and-wordpress-performance/

## Unverified

- The default `pm` mode and default `max_children` per pool on current stacks.
  Confirm from a real pool file before quoting defaults.
