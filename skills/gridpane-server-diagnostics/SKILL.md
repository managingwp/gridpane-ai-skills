---
name: gridpane-server-diagnostics
description: >-
  Use when you need to inspect the health of a GridPane server rather than fix
  one site: checking load, memory and swap, disk and inodes, service states,
  PHP-FPM pool saturation (max_children), MySQL/MariaDB processlist and slow log,
  Redis memory, and web server error logs. Also use for "which pool is hitting
  max_children", "is the database the bottleneck", "what is eating disk", or
  "which site is causing the load" on a GridPane box. Read-only. For a specific
  broken site start with gridpane-incident-triage; to action a fix use
  gridpane-gp-cli or the relevant write skill.
---

# gridpane-server-diagnostics

Read-only diagnosis of a GridPane server. This skill collects evidence and tells
you what it means; it does not change anything. Use it to answer "is this a
server problem or a single-site problem", and "which resource and which site".

Load `gridpane-core` first for paths, `gp` conventions and the safety protocol.
Read the reference that matches the symptom:

- `references/php-fpm.md` — per-site pools, `max_children` saturation, PHP slow log.
- `references/mysql.md` — processlist, table locks, slow log, connection and buffer checks.
- `references/logs.md` — which log answers which question, with one-liners.
- `gridpane-core/references/gridenv.md` — `/root/gridenv` server state (active
  sites, PHP versions, cache backends, Monit thresholds). Read individual
  non-secret keys only.

`scripts/gp-healthcheck.sh` runs the whole first pass in one shot. It also reports
the GridPane environment (`/root/gridenv`): server version/build, active-site
count, whether the Redis page/object caches are configured, and (with
`--site`) the site's recorded page-cache method (`cache-type`) and object-cache
state from its per-site env.

```bash
# [READ] Whole-server snapshot as text (add --json for machine output).
scripts/gp-healthcheck.sh
```

```bash
# [READ] Restrict per-site sections to one domain.
scripts/gp-healthcheck.sh --site example.com
```

## Prerequisites

- Root (or sudo) over SSH.
- `gridpane-core` loaded.
- Know whether the box is Nginx or OpenLiteSpeed; log paths and the PHP model
  differ. Confirm with `gp ngx -status` (Nginx) or
  `systemctl is-active lshttpd` (OLS).

## Workflow

Work top down: resources → services → PHP → database → cache → web errors.
Stop when you find the resource that is actually saturated; a healthy metric is
not the problem.

1. **Load and memory.** Is the box out of RAM and swapping?
2. **Disk and inodes.** A full disk breaks far more than it at first appears.
3. **Services.** Is something down or being restarted by Monit?
4. **PHP workers.** Nginx: is a PHP-FPM pool saturated on `max_children`? OLS:
   LSAPI has no PHP-FPM pools; check `lshttpd` and its logs.
5. **Database.** Processlist locks, slow queries, connections, InnoDB buffer.
6. **Redis.** Is the object/page cache out of memory?
7. **Web server errors.** What is PHP/Nginx actually complaining about?
8. **GridPane environment.** Read `/root/gridenv` for the active-site list, PHP
   versions, cache backends and this server's Monit thresholds.
9. **Recent GridPane activity.** Did something change just before the symptom?

Useful first-pass commands:

```bash
# [READ] Resource overview: load, memory, swap, disk and inodes.
uptime
free -h
df -hP /
df -iP /
```

```bash
# [READ] Service states across the stack.
systemctl --no-pager --type=service --state=failed
```

```bash
# [READ] OLS: service state and logs (skip on Nginx).
systemctl is-active lshttpd
gpols log httpd
tail -n 100 /usr/local/lsws/logs/stderr.log
```

```bash
# [READ] What GridPane did recently (often explains an abrupt change).
tail -n 100 /var/log/gridpane.log
```

## Verify

Interpretation guidance rather than a fix. You have found the cause when one
resource is clearly exhausted and the timing matches the symptom:

- **Load** high *and* `wa` (I/O wait) high → disk/IO bound.
- **Swap** used beyond ~10-20% of RAM → RAM starved; requests slow, 502/504 likely.
- **PHP pool** reporting it reached `pm.max_children` → PHP worker starvation.
- **MySQL** processlist full of `Waiting for table metadata lock` → table locking.
- **Disk/inodes** near 100% → the classic cause of sudden, wide failures.
- **OLS:** `lshttpd` inactive/restarting, or `oops`/LSAPI errors in
  `/usr/local/lsws/logs/error.log` / `stderr.log` → web-server problem.

## Rollback

Not applicable: this skill only reads. Any change is made by a write skill, which
must carry its own backup and rollback.

## Gotchas

- **Do not restart services to "see if it helps" while diagnosing.** It destroys
  evidence and is a [WRITE]. Diagnose first; restart only as a confirmed fix.
- **`show processlist` needs a MySQL login.** Use `gp mysql login root`
  (interactive). Never paste the password into a transcript.
- **Slow logs are usually off**, and the KB says to turn them off again after
  use. Enabling them edits server config, so it is a [WRITE] with a rollback.
- **Monit restarts services automatically.** A service showing "active" may have
  just been auto-restarted; check `/var/log/monit.log` for recent restarts.
- **A server-wide symptom is not always server-wide cause.** One runaway site can
  exhaust shared PHP workers, RAM or the database for everyone.
- **OLS has no PHP-FPM pools.** `php-fpm` pools and logs do not exist there; PHP
  runs via LSAPI and the web server process is `lshttpd`.

## Sources

- PHP Slow Log — https://gridpane.com/kb/using-the-php-slow-log/
- MySQL Slow Log — https://gridpane.com/kb/using-the-mysql-slow-log/
- Diagnosing 502 Errors — https://gridpane.com/kb/diagnosing-502-errors/
- GridPane Logs — https://gridpane.com/kb/gridpane-logs-how-to-find-them-and-when-to-use-them/
- Useful Commands — https://gridpane.com/kb/useful-commands-for-managing-gridpane-servers/

Last verified: 2026-10-09
