# MySQL / MariaDB on GridPane

Engine and version checks, processlist and locks, the slow query log, connection
and buffer checks, and finding the heavy database.

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

## Which engine and version?

The engine decides which column types and collations exist, so settle it before
reading a schema or promising a migration.

```sql
-- [READ] Engine, version and the server default collation.
SELECT VERSION(), @@version_comment, @@collation_server;
```

```bash
# [READ] The client banner, without logging in. The format changed between
# MariaDB releases, so do not match a fixed string:
#   10.11: "mysql  Ver 15.1 Distrib 10.11.18-MariaDB, ..."  (Ver is the CLIENT version)
#   11.8:  "mysql from 11.8.8-MariaDB, client 15.2 ..."     (version follows "from")
mysql --version
```

What the version gates:

| Need | Present on |
|---|---|
| `utf8mb4_uca1400_*` collations | MariaDB 11.x; not Percona |
| `utf8mb4_0900_*` collations | MySQL and Percona 8.x; not MariaDB 10.11 |
| `VECTOR` column type and vector indexes | MariaDB 11.7 and newer — see **Unverified** below |

A restore or clone refuses when the destination engine cannot represent what the
source uses, instead of importing part of a database; see
`gridpane-incident-triage`.

### Does a database use a vector column?

Cheap and safe on any engine: it returns no rows when nothing matches.

```sql
-- [READ] Columns using a type beyond the usual scalars, per schema.
SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM information_schema.COLUMNS
WHERE DATA_TYPE = 'vector';
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
- The slow-log path is `/var/log/mysql/slow.log` — the path GridPane's own
  scripts use (`lib/stack.sh`). The KB page is inconsistent about it; trust the
  server path above.
- The engine is Percona on the captured stack; the scripts also detect MariaDB
  (`lib/services.sh`), and reference `mysql.service`. Confirm on a MariaDB box
  before quoting unit names. The version matrix per OS stack is in
  `gridpane-core/references/stack-overview.md`.
- The 10.11 banner's `Ver 15.1` is the **client protocol** version, not the
  server. Reading it as the server version is the classic misread on MariaDB.

## Unverified

- **MariaDB vector search.** GridPane staff describe MariaDB 11.8 (Ubuntu 26.04
  servers) as supporting `VECTOR` columns and vector indexes, with these restore
  behaviours: a database containing a vector index restores one thread per table
  because parallelised myloader deadlocks, the index is rebuilt rather than
  copied, the vector index cache defaults to 16 MB, and embeddings cost about
  6 KB per row at 1,536 dimensions. The 2026-10-14 `gpcli` snapshot contains no
  `VECTOR` handling, so none of this is confirmed in code and none of it is
  guidance yet. See `OPEN-QUESTIONS.md`.

## Sources

- Using the MySQL Slow Log — https://gridpane.com/kb/using-the-mysql-slow-log/
- Diagnosing 502 Errors (table locking, RAM guidance) — https://gridpane.com/kb/diagnosing-502-errors/
- How to Optimize Database Performance with MySQLTuner — https://gridpane.com/kb/how-to-optimize-database-performance-with-mysqltuner/
- Configure MySQL — https://gridpane.com/kb/configure-mysql/
- MariaDB 11.7+ vector search support timeline — GridPane community forum, staff
  replies 2026-09-22 and 2026-09-25 (pasted by the maintainer 2026-11-05; URL not
  yet recorded, see `OPEN-QUESTIONS.md`)

Last verified: 2026-11-05
