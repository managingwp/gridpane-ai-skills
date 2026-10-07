# MySQL / MariaDB on GridPane

Processlist and locks, the slow query log, connection and buffer checks, and
finding the heavy database.

## Log in

```bash
# [READ] Open an interactive MySQL root session (preferred; password never shown).
gp mysql login root
```

```bash
# [READ] Print the MySQL root password (for a remote client). Do not paste the
# output into a transcript or commit it anywhere.
gp mysql get-pass root
```

## Processlist and table locking

Once logged in:

```sql
-- [READ] Active connections and queries.
show processlist;
```

The signal to look for is many rows in state **`Waiting for table metadata
lock`** with a long `Time`. That means a plugin or backup job is holding a table
lock and everything else is queued behind it. In the 502 triage article this is
seen with Blogvault, MalCare, Rank Math and WPvivid.

```
| 40581 | VOO_example_com | localhost | VOO_example_com | Query | 14241 | Waiting for table metadata lock | DROP TABLE IF EXISTS wp_bv_ip_store |
```

If table locking is the cause, a MySQL restart clears it ([WRITE]):

```bash
# [WRITE] Restart MySQL to release metadata locks.
# Effect: clears locked tables; brief DB outage for all sites on the server.
# Blast radius: all sites on the server.
# Backup: not applicable (no data change); note it is disruptive.
# Rollback: none needed; service comes back automatically.
# Confirm before running.
gp mysql restart
```

Also check whether locking recurs at the top of each hour: that points at the
Borg backup job locking tables while it runs. Adjust the backup schedule rather
than restarting MySQL every hour.

## Slow query log

Records queries slower than `long_query_time` seconds. Best for database-heavy
sites such as WooCommerce.

```bash
# [WRITE] Enable the MySQL slow query log (1 = on).
# Effect: starts logging slow queries server-wide.
# Blast radius: all sites on the server (log verbosity, not behaviour).
# Backup: none (a config toggle via gp).
# Rollback: `gp stack mysql -long-query-time 0` to disable.
# Confirm before running.
gp stack mysql -slow-query-log 1
```

```bash
# [WRITE] Log queries slower than 10 seconds.
gp stack mysql -long-query-time 10
```

```bash
# [WRITE] Apply the change.
gp mysql restart
```

Read it:

```bash
# [READ] View the slow query log.
cat /var/log/mysql/slow.log
```

Each entry has the query, timestamp and duration. Always turn slow logging off
again after debugging.

## Connections and buffers

Useful stack settings (all [WRITE], server-wide):

| Setting | Command |
|---|---|
| Max connections | `gp stack mysql -max-connections {value}` |
| InnoDB buffer pool size | `gp stack mysql -innodb-buffer-pool-size {value}` |
| Buffer pool instances | `gp stack mysql -innodb-buffer-pool-instances {value}` |
| Long query time | `gp stack mysql -long-query-time {value}` |
| Slow query log | `gp stack mysql -slow-query-log {value}` |

Check current pressure inside MySQL:

```sql
-- [READ] How close are we to the connection ceiling?
show status like 'Threads_connected';
show status like 'Max_used_connections';
```

If `Max_used_connections` approaches `max_connections`, the app is exhausting the
pool; find the leaking site rather than only raising the limit.

## Finding the heavy database / site

```bash
# [READ] Database size per site (directory sizes, not exact but good for ranking).
du -h --max-depth=1 /var/lib/mysql | sort -h
```

In `show processlist`, the `db` column names the database, which usually encodes
the site. That is how you attribute load to a site.

```bash
# [READ] File (non-database) disk use per site, for comparison.
du -h --max-depth=1 /var/www | sort -h
```

## RAM sizing rule of thumb

The 502 triage article's guidance: total MySQL size should not exceed ~50% of RAM
on 2-8 GB servers; MySQL and Redis are the main RAM consumers. A server using
swap heavily while MySQL holds a large buffer pool is over-committed.

## Gotchas

- Restarting MySQL is server-wide and briefly drops all sites' DB access. Treat
  it as a confirmed [WRITE], not a casual fix.
- Slow logging adds overhead; leave it off when not debugging.
- The exact slow-log path is inconsistent in the KB — verify on the server. See
  `gridpane-core/references/paths.md`.

## Sources

- Using the MySQL Slow Log — https://gridpane.com/kb/using-the-mysql-slow-log/
- Diagnosing 502 Errors (table locking, RAM guidance) — https://gridpane.com/kb/diagnosing-502-errors/
- How to Optimize Database Performance with MySQLTuner — https://gridpane.com/kb/how-to-optimize-database-performance-with-mysqltuner/
- Configure MySQL — https://gridpane.com/kb/configure-mysql/

Last verified: 2026-10-07
