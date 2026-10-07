---
name: gridpane-incident-triage
description: >-
  Use when a GridPane-managed site or server is failing and you need a path to
  the cause: a site is down or timing out, returning 502/503/504/500, showing a
  white screen, suddenly slow, a server alert fired (high load, high memory, disk
  full), SSL is failing, a redirect loop appears, or the database won't connect.
  Routes to gridpane-server-diagnostics for server resources,
  gridpane-security for WAF/Cloudflare/compromise, and gridpane-wordpress for
  plugin/cache causes. Do not use for routine tuning with no symptom, or for
  servers that are not managed by GridPane.
---

# gridpane-incident-triage

The umbrella incident workflow for GridPane. It routes: it does not duplicate the
diagnostic or fix skills. Start here when something is broken and you do not yet
know why. Load `gridpane-core` first.

The goal order is always the same: **stabilise, then find the cause, then fix with
confirmation, then write it up.**

## Prerequisites

- Root (or sudo) over SSH, or the GridPane dashboard for Monit/log viewing.
- `gridpane-core` loaded.
- The failing symptom, the affected domain(s), when it started, and what changed
  around then (deploy, plugin update, DNS/Cloudflare change, certificate renewal).

## Workflow

1. **Scope it.** One site, several sites, or the whole server? A single site
   points at code/plugins; everybody points at a shared resource.
2. **Capture state before touching anything.** Run read-only checks first.
   Restarting or clearing cache destroys evidence.
3. **Follow the symptom below.** Each row gives the first three [READ] checks,
   likely causes ranked, where to hand off, and the standard fix.
4. **Propose the fix, get confirmation.** Use the template in
   `gridpane-core/references/safety.md`. Back up config first; validate before
   reload.
5. **Verify, then write it up.** Confirm with an observable check and record the
   incident with `references/rca-template.md`.

Universal first three checks:

```bash
# [READ] 1. Is the box resource-starved? Load, memory, swap, disk.
uptime && free -h && df -hP /
```

```bash
# [READ] 2. Did something change recently?
tail -n 100 /var/log/gridpane.log
```

```bash
# [READ] 3. What is the web server saying for this site?
tail -n 50 /var/log/nginx/example.com.error.log
```

## Symptom decision tree

| Symptom | First checks | Likely causes (ranked) | Hand off to | Standard fix |
|---|---|---|---|---|
| Site down / times out | `curl -I` from server; Monit; error log | Web server down; PHP down; DNS/Cloudflare; origin blocked | `server-diagnostics`, `security` | Restart the downed service ([WRITE]); fix DNS/proxy |
| 502 Bad Gateway | Monit PHP; `free -h`; error log | PHP-FPM down/saturated; OOM/swap; DB table locks; slow plugin | `server-diagnostics/php-fpm`, `mysql` | Free RAM or raise pool ([WRITE]); restart PHP ([WRITE]) |
| 503 Service Unavailable | OLS `stderr.log`; PHP service | PHP crashed; pool exhausted (OLS) | `server-diagnostics` | Restart PHP service ([WRITE]); raise limits |
| 504 Gateway Timeout | PHP slow log; MySQL slow log; load | Long-running PHP/DB; low max-exec-time | `server-diagnostics` | Fix the slow plugin/query; raise timeouts ([WRITE]) |
| 500 / white screen | Site error log; WP debug; `--skip-plugins` | Fatal PHP error; bad plugin/theme; bad `wp-config` | `wordpress` | Bisect plugins; fix code; see WP debug |
| Slow site (server OK) | PHP slow log; MySQL slow log; Query Monitor | Uncached pages; slow plugin; unindexed queries | `server-diagnostics`, `wordpress` | Fix query/plugin; verify caching |
| High load alert | `top`/`htop`; load; pools; processlist | Runaway PHP; DB; bot traffic; noisy neighbour/steal | `server-diagnostics`, `security` | Stop the cause; block bots; scale |
| Disk full | `df -hP /`; `df -iP /`; `du` | Log growth; backups; uploads; inodes | `server-diagnostics/logs` | Clear/rotate logs ([WRITE]); grow disk |
| SSL error / renewal fail | `ssl-provision.log`; cert dates; DNS | DNS not pointed; rate limit; challenge path blocked | `incident-triage` steps + `security` | Fix DNS then re-provision |
| Redirect loop | `curl -I`; Cloudflare SSL mode; wp options | Cloudflare Flexible + origin redirect; site URL mismatch | `security/cloudflare`, `wordpress` | Set Full (strict); fix site URL |
| DB connection error | MySQL service; error log; processlist | MySQL down; too many connections; disk full | `server-diagnostics/mysql` | Restart MySQL ([WRITE]); raise connections |

## 502 Bad Gateway

The most common GridPane incident. 502 means Nginx/OLS could not get a valid
response from PHP-FPM in time.

```bash
# [READ] Is PHP even up? Check Monit state and the FPM log.
systemctl is-active "php$(ls /etc/php | head -n1)-fpm" || true
grep -i 'max_children' /var/log/php/*/fpm.log | tail -n 20
```

```bash
# [READ] Memory and swap: excessive swap is a classic 502 cause.
free -h
```

```bash
# [READ] Table locking as a 502 cause.
gp mysql login root   # then: show processlist;
```

Ranked causes: PHP-FPM down or saturated on `max_children`; excessive swap/OOM;
database table locking; one slow plugin holding workers. If **other sites on the
server are fine**, the cause is almost certainly that site's code, not the stack.

Standard fix: free RAM or raise the pool ([WRITE], see
`server-diagnostics/references/php-fpm.md`); if tables are locked, a confirmed
MySQL restart clears it ([WRITE]). Never restart before capturing the processlist
and logs.

## 504 / slow site

```bash
# [READ] Turn on PHP slow logging for the site (configuration change to follow).
# First read the current setting so you can restore it:
grep -i slowlog /etc/php/*/fpm/pool.d/example.com.conf || true
```

Then enable the PHP slow log and the MySQL slow log as documented in
`server-diagnostics`. A slow log almost always names a plugin or an unindexed
query.

## Disk full

```bash
# [READ] Where is the space going? Files per site, then inodes.
du -h --max-depth=1 /var/www | sort -h | tail -n 20
df -iP /
```

```bash
# [READ] Common large consumers: backups and logs.
du -h --max-depth=1 /var/log | sort -h | tail -n 20
```

Clearing or rotating logs and pruning old backups is [WRITE] (or [DESTRUCTIVE]
for backup purge). Confirm the target and the retention impact before deleting
anything.

## SSL error

```bash
# [READ] Why did provisioning fail? DNS first, then the log.
tail -n 50 /var/www/example.com/logs/ssl-provision.log
```

The usual cause is DNS not pointing at the server, or a Let's Encrypt rate limit.
Certificates provisioned by webroot vs DNS API renew through different logs
(`certbot.monitoring.log` vs `acme.monitoring.log`; see `gridpane-core` paths).

## Redirect loop

Almost always Cloudflare SSL mode plus an origin redirect. Check the SSL mode in
Cloudflare (should be **Full (strict)**) and the WordPress site URL.

```bash
# [READ] See the redirect chain.
curl -sSI https://example.com | grep -iE '^HTTP|^location'
```

Hand off to `gridpane-security/references/cloudflare.md` and `gridpane-wordpress`.

## Verify

The incident is resolved when the original symptom no longer reproduces **and**
the resource that caused it is back in normal range: `curl -I` returns 200/30x,
Monit services are OK, and load/swap/disk are sane.

## Rollback

Each fix is made by a write skill and must carry its own rollback. If a fix makes
things worse, restore the `.bak-<timestamp>` config copy and reload the last
known-good state; for a service restart, the rollback is the service coming back
(no data change).

## Gotchas

- **Capture before you clear.** Restarting PHP/MySQL or purging cache erases the
  evidence that would have identified the cause.
- **Do not bulk-fix the fleet.** A fleet-wide action for a single-site symptom
  can turn one incident into many.
- **Cloudflare masks the origin.** Before blaming the server, confirm the request
  actually reached it (real-IP, DNS, SSL mode).
- **`all-sites` and bare `gp fix cached` are server-wide**, not single-site.

## Sources

- Diagnosing 502 Errors — https://gridpane.com/kb/diagnosing-502-errors/
- Diagnosing 503 Errors — https://gridpane.com/kb/diagnosing-503-errors/
- Diagnosing HTTP 500 Errors — https://gridpane.com/kb/diagnosing-http-500-internal-server-errors/
- Diagnosing Redirect Issues — https://gridpane.com/kb/diagnosing-redirect-issues/
- Diagnosing and Fixing SSL Certificate Issues — https://gridpane.com/kb/diagnosing-and-fixing-ssl-certificate-issues/
- Sites are Down Part 2: Practical Troubleshooting — https://gridpane.com/kb/sites-are-down-part-2-practical-troubleshooting/

See `references/rca-template.md` for the write-up format.

Last verified: 2026-10-07
