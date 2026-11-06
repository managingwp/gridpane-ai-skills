# Backups (v2, Duplicacy)

What the `gpbup`/`gpbup2` entry points actually do, how the panel is told a
backup finished, and how to take one local backup on demand. Read this when a
backup "succeeds" without producing a revision, when the panel's backup buttons
spin, or when local backups are configured but never run.

It also covers the two mydumper/myloader generations and the dump/load timeout
files: those decide whether a dump can be loaded at all, and whether a large one
finishes inside the limit.

For missing revisions after site deletion/recreation, read
[missing-backups.md](missing-backups.md): historical evidence, storage-specific
snapshot IDs, alternate buckets and the recovery hand-off boundary.

The command table lives in `command-reference.md`; this file is the behaviour
behind it. Facts are traced to the deployed script snapshot (`lib/gpbup.sh`),
see `gridpane-core/references/sources.md`.

## Model

- Both wrappers are one line: `set -- "backup" "$@"` then source
  `/usr/local/bin/gp`, so every call lands in `gpbup::main`.
- Local storage is one shared Duplicacy repository per server at
  `/opt/gridpane/backups/duplications`. Each site gets its own Duplicacy
  preferences at `/var/www/{site}/.duplicacy`, initialised on demand by
  `gpbup::checkrepoinit`.
- A backup is a database dump (mydumper, `database-<epoch>` in the site root —
  which generation runs matters, see below) plus a `duplicacy backup` revision of
  `/var/www/{site}`. Revisions carry a tag: `gp-automated` for the scheduled
  path, `<epoch>-manual` for the manual path.
- Each storage has its own toggle in `/var/www/{site}/logs/backups.env`
  (`Local-Backups:ON|OFF`, `Remote-Backups:ON|OFF`). The schedule lives in
  `/var/www/{site}/logs/{site}.env` and, for the cron scheduler,
  `/etc/cron.d/backup-{interval}-{storage}-{site}`.

## The dump tools: two mydumper generations

Backups, clones and staging all dump with mydumper and load with myloader, and
two generations coexist on every current server:

| Generation | Version | Location | On `PATH` |
|---|---|---|---|
| 0 (baseline) | 0.14.5-2 | `/usr/bin/mydumper`, `/usr/bin/myloader` (dpkg) | yes |
| 1 (current) | 1.0.3 | `/usr/local/bin/mydumper-1.0.3/bin`, staged from `/opt/gridpane/mydumper/1.0.3` | no, deliberately |

Generation 1 is kept off `PATH` so that a bare `mydumper` still resolves to
generation 0: an unconverted call site keeps its old behaviour instead of
silently writing a 1.0.3 dump that older readers classify as baseline.

**The generations cannot load each other's output.** Measured on a
Ubuntu 26.04 / MariaDB 11.8 server:

| Dump made by | Loaded by | Result |
|---|---|---|
| 1.0.3 | 0.14.5 | `rc=139` SEGFAULT, 0 tables, no output at all |
| 0.14.5 | 1.0.3 | `rc=134`, `Section [config] was not found on metadata file` |

The dangerous direction is new → old, because a segfault writes no `CRITICAL`
line for the import parsers to catch: the restore looks like it did nothing
rather than like it failed.

Generation 1 writes `.gp-dump-version` inside the dump directory. That dotfile is
the only reliable generation marker, because 1.0.3 still prints `# Started dump
at`, which the restore path's metadata shim reads as a baseline dump. It lives
inside the dump directory on purpose: `dir/*` skips dotfiles, so it cannot leak
into the wp-cli fallback paths, and duplicacy's `database-*` include patterns
carry it into the revision.

Generation 1 also takes different flags, and they follow the binary rather than
the OS: `--lock-all-tables` for 0.14.5, `--sync-thread-lock-mode=LOCK_ALL` plus
`--clear` for 1.0.3. `--trx-tables=0` is generation 1 only and is passed when the
schema holds a non-transactional table, because 1.0.3 otherwise assumes an
all-InnoDB schema and aborts on the first MyISAM or MEMORY table. Ordinary
WordPress sites carry those (Action Scheduler, Gravity Forms, Wordfence's
`wfls_role_counts`, `wp_links`).

## Long dumps and loads: the timeout files

Every dump and load runs under `timeout`, defaulting to **10800 seconds (3
hours)**. A large database can exceed that, and the run then fails at the limit
rather than because anything is wrong with the site.

| File | Read on | Applies to | Default |
|---|---|---|---|
| `/root/mydumper.timeout` | source server | backups, clone and staging exports | 10800 |
| `/root/myloader.timeout` | destination server | restores, clone and staging imports | 10800 |

Each file holds one integer number of seconds. A missing or non-numeric file
falls back to the default, so a malformed file silently keeps 3 hours.

```bash
# [WRITE] Raise the dump limit to 6 hours on this server.
# Effect: dumps may run up to 21600s; nothing else changes.
# Blast radius: this server's own dump runs (backups and clone exports).
# Backup: note the previous value; there is no file to copy when it is absent.
# Rollback: rm /root/mydumper.timeout (back to the 10800 default).
# Confirm before running.
echo 21600 > /root/mydumper.timeout
```

```bash
# [WRITE] Raise the load limit to 6 hours on the destination server.
# Effect: restores and clone imports may run up to 21600s.
# Blast radius: this server's own load runs.
# Backup: note the previous value; there is no file to copy when it is absent.
# Rollback: rm /root/myloader.timeout (back to the 10800 default).
# Confirm before running.
echo 21600 > /root/myloader.timeout
```

Set them on the right side of the transfer: a slow backup is a source problem, a
slow restore or clone import is a destination problem.

## Entry points

| Command | Runs where | Tag | Toggle required |
|---|---|---|---|
| `-run-single-site {storage}` | queued in task-spooler | `gp-automated` | yes |
| `-single-site {storage}` | foreground (the queued job) | `gp-automated` | yes |
| `-local-single-site` | foreground | `<epoch>-manual` | no |
| `-remote-single-site {storage}` | foreground | `<epoch>-manual` | no |

`-run-single-site` is what GridPane writes into the cron file, so it is the
scheduled-run path. It backs nothing up itself: it queues
`gp backup {site} -single-site {storage}` on the task-spooler socket
`/tmp/ts-socket-backups.<uid>` (installed on demand, one job at a time) and
returns immediately, printing the task id. A plain `tsp -l` looks empty because
it uses the default socket.

Both scheduled arms end in `gpbup::backup {site} {storage}`, which for `local`:

1. requires `Local-Backups:ON`; when local backups are off it backs up
   **nothing** and still exits 0, so a zero exit is not proof a backup exists. A
   skipped run finishes in about a second and
   `active.backups.monitoring.log` stops at
   `Local backups are NOT enabled for {site}.` with no `Backup of {site} Done!`;
2. waits for the per-site backup lock rather than skipping; if the lock is not
   obtained the arm returns 1, so a queued job is not recorded as a success;
3. refuses when free space on `/opt/gridpane/backups/duplications` minus the
   database dump would fall below `backup-max-disk-usage`% of the filesystem
   (default 10%);
4. dumps the database, then runs `duplicacy backup -t gp-automated`, and does
   **not** prune. Retention is the separate prune schedule's job.

## One-off local backup

The manual path never reads the `Local-Backups` toggle, which makes it the right
tool for a single backup on a site whose local schedule is off.

```bash
# [WRITE] One manual local backup. Blast radius: this site only; creates a local
# revision and initialises /var/www/{site}/.duplicacy if this is the first one.
# Rollback: purge the revision if unwanted. Confirm before running.
# Run inside tmux/screen: an SSH drop skips the completion callback (below) and
# the panel is left spinning.
gpbup example.com -local-single-site
```

It is tagged `<epoch>-manual`, takes the lock without waiting, checks the disk
threshold after the dump, and refreshes the panel's available-backups list. What
a good run looks like in `/var/www/{site}/logs/manual-backups.log`:

```
Manual Local database export success!
Backup for /var/www/example.com at revision 1 completed
Manual Local Backup Success!
```

then an `available-backups` refresh whose payload carries
`"local":{"manual":"<date>"}` — that is the panel's proof the revision exists.
`Done!` closes the run.

## The panel's backup buttons

The panel re-enables its backup buttons only when the server posts
`/backups/backup`. That call is made from exactly one place,
`gpbup::callback::manual_backup_status`, so **only the manual paths report
completion**, on success *and* on failure. Scheduled-form runs never post it, and
neither does a manual run that dies before the callback — a refusal from the
legacy PID lockfile `exit 1`s early, for example. A spinner that never clears is
usually a scheduled-form run that no-opped or failed without a callback.

The panel's own local backup button arrives as a scheduled-form run: a
`-single-site local` task in the queue and an entry in
`active.backups.monitoring.log`, not in `manual-backups.log`. With the local
toggle `OFF` that run no-ops and the spinner stays. CLI one-offs are unaffected.

Fix the spinner by letting a manual backup finish (above). When nothing is
running and it still spins, post the completion callback yourself:

```bash
# [WRITE] Panel state only: posts /backups/backup as failed for this site and
# re-enables the buttons. No backup runs and no site data changes.
# Confirm before running.
gp -function-run 'gpbup::callback::manual_backup_status 1 example.com local'
```

Pass `1` (failed) unless a backup really completed; `0` claims a success the app
will record in the site's backup history. The raw form, when you want to see the
request:

```bash
# [WRITE] Same POST, spelled out. The printed response contains the server key:
# do not paste it into a ticket or transcript.
gp callback /backups/backup -- site_url=example.com site_id={site_id} \
  server_ip={server_ip} server_id={server_id} status=failed service=local \
  -s 'details="Backup Processes Complete: example.com - local backup failed"'
```

Only do this when `TS_SOCKET=/tmp/ts-socket-backups.0 tsp -l` shows no `running`
row and `/run/gridpane/backups/{site}.lock` is free: clearing the spinner while a
real backup is in flight hides the problem instead of reporting it.

## Locks and the queue

Two locks can refuse a run:

- `/run/gridpane/backups/{site}.lock` — the flock held by a live backup. The
  stamp inside names pid, start time, type and storage. Manual backups do not
  wait, so a holder means the run is refused and the panel keeps spinning. Do
  not delete this file: closing the holder's descriptor is what releases it.
- `/opt/gridpane/backups/{site}-{storage}-{uuid}.pid` — the legacy PID lockfile.
  A live pid, or any `duplicacy` process for the site, refuses the run. A dead
  pid with no duplicacy process is cleaned up by the next run.

## Inspecting the queue

All scheduled runs share one task-spooler slot, so one hung job stalls every
other site's schedule. The script waits 20 minutes for a holder and treats one
older than an hour as stuck; killing a hung task releases its flock with the
process, and the next run cleans up the stale PID file.

A scheduled run is a task-spooler job on a socket of its own, so the question
"is a backup running?" is answered by the queue, not by `ps`:

```bash
# [READ] The backup queue: queued, running and finished jobs.
TS_SOCKET=/tmp/ts-socket-backups.$(id -u) tsp -l
```

`$(id -u)` is the uid of the user that queued the job: root for the scheduled
runs, so the socket is `/tmp/ts-socket-backups.0`. A plain `tsp -l` reads the
default socket (`$TMPDIR/socket-ts.<uid>`) and therefore looks empty even while
a backup is running — the wrong socket, not an idle queue.

A socket with no jobs on it — the wrong socket, or a queue whose finished
results were cleared with `tsp -C` — prints the header and no rows:

```
ID   State      Output               E-Level  Times(r/u/s)   Command [run=0/1]
```

`run=` is slots in use out of slots available: `run=0/1` means nothing is
running and the queue's one slot is free. A real row adds a state (`running`,
`queued`, `finished`, `skipped`), the path of its `Output` file and the command.

Two traps:

- **`-L` is a label, not a queue.** A job is enqueued as `tsp -L backups …`
  purely so the listing is readable — `tsp(1)` says the label "will appear next
  to its command when listing the queue". Every job on the socket is listed
  whether or not you pass `-L`, and `tsp -L backups` with no command just lists
  the default queue. Do not go looking for a queue named `backups`.
- **`ps` shows `gp backup`, not `gpbup`.** The wrapper resolves to
  `/usr/local/bin/gp backup {site} -single-site {storage}` and is queued as
  `tsp -L backups /usr/local/bin/gp backup …`, so `ps aux | grep gpbup` finds
  nothing while a backup runs. Look for `gp backup` in `ps`, or read the queue
  above.

Once a row is `running`, get its output path, full output, live tail and pid:

```bash
# [READ] One job's output file, full output, tail and pid. Substitute {id} from
# the tsp -l row; -t keeps printing while the job is still running.
TS_SOCKET=/tmp/ts-socket-backups.$(id -u) tsp -o {id}
TS_SOCKET=/tmp/ts-socket-backups.$(id -u) tsp -c {id}
TS_SOCKET=/tmp/ts-socket-backups.$(id -u) tsp -t {id}
TS_SOCKET=/tmp/ts-socket-backups.$(id -u) tsp -p {id}
```

When the socket is not where you expect it, ask the live process instead of
guessing:

```bash
# [READ] Socket discovery. {pid} is the pid from `tsp -p {id}`. The first half
# prints the TS_* variables that process inherited (TS_SOCKET, TS_SLOTS); the
# second lists every task-spooler socket on the box and the process holding it.
tr '\0' '\n' < /proc/{pid}/environ | grep -E '^TS_'
ss -xlp | grep -i ts
```

Before calling a job stuck, prove it is not working:

```bash
# [READ] Hung or busy? A real run has a duplicacy (or rclone) child and an
# output file that keeps growing. Check both, twice, before touching the job.
pgrep -a -P {pid}
stat -c '%y %n' "{output}"
```

No child and an output file whose mtime has not moved for far longer than a
normal run means hung; a child with recent output means busy, and the fix is to
wait. Only then abort it:

```bash
# [DESTRUCTIVE] SIGTERM to the job's process group. Only after the checks
# above show it is hung. Confirm before running.
TS_SOCKET=/tmp/ts-socket-backups.$(id -u) tsp -k {id}
```

Blast radius: this one run is aborted, no revision is produced for it, and a
half-written database dump (`database-<epoch>`) can be left in the site root —
remove it before the next run or the disk threshold sees it. The queue's single
slot stays occupied until the process group actually dies, so nothing else
starts until then. Precondition: `pgrep -P` showed no `duplicacy`/`rclone`
child. Rollback: fix the cause and re-run the backup (a manual
`-local-single-site`/`-remote-single-site` if you need it now), then let the
next scheduled run clean up the stale PID file.

## Cron can outlive the toggle

`-set-backup-schedule` writes `/etc/cron.d/backup-{interval}-{storage}-{site}`
when *any* backup type is enabled for the site, not the one the cron is for. A
site with `Remote-Backups:ON` and `Local-Backups:OFF` can therefore carry a daily
local cron whose every run exits 0 without backing anything up. Check
`/var/www/{site}/logs/backups.env`, not the cron file, when deciding whether
local backups actually run.

If you want local backups from the panel, the toggle has to be `ON`, which also
means GridPane keeps a schedule for that site; set the interval you actually
want rather than deleting the cron. Deleting the cron is a [WRITE] on GridPane
state and the app can recreate it the next time a local schedule is saved.

## Where to look

| File | Contents |
|---|---|
| `/opt/gridpane/backup.log` | All backup activity, one line per event |
| `/opt/gridpane/active.backups.monitoring.log` | Scheduled (`-single-site`) runs, including the "not enabled" no-op |
| `/var/www/{site}/logs/manual-backups.log` | Manual runs, plus the available-backups refresh payload |
| `/var/www/{site}/logs/backups.env` | `Local-Backups` / `Remote-Backups` toggles |
| `/var/www/{site}/logs/{site}.env` | Backup and prune schedule settings |

Last verified: 2026-11-05 against the `tmp/gpcli` snapshot
(`usr/local/bin/gpbup`, `gpbup2`, `lib/gpbup.sh`, `lib/clone.sh`,
`lib/gridpane.sh`), a maintainer-supplied run on a GridPane server, and the
2026-11-04 backup queue capture (`gridpane-core/references/sources.md`).
