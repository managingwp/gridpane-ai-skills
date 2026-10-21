# Backups (v2, Duplicacy)

What the `gpbup`/`gpbup2` entry points actually do, how the panel is told a
backup finished, and how to take one local backup on demand. Read this when a
backup "succeeds" without producing a revision, when the panel's backup buttons
spin, or when local backups are configured but never run.

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
- A backup is a database dump (mydumper, `database-<epoch>` in the site root)
  plus a `duplicacy backup` revision of `/var/www/{site}`. Revisions carry a tag:
  `gp-automated` for the scheduled path, `<epoch>-manual` for the manual path.
- Each storage has its own toggle in `/var/www/{site}/logs/backups.env`
  (`Local-Backups:ON|OFF`, `Remote-Backups:ON|OFF`). The schedule lives in
  `/var/www/{site}/logs/{site}.env` and, for the cron scheduler,
  `/etc/cron.d/backup-{interval}-{storage}-{site}`.

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

All scheduled runs share one task-spooler slot, so one hung job stalls every
other site's schedule. Inspect with `TS_SOCKET=/tmp/ts-socket-backups.0 tsp -l`
(look for a `running` row) and read the task's `Output` file directly. The script
waits 20 minutes for a holder and treats one older than an hour as stuck;
killing a hung task releases its flock with the process, and the next run cleans
up the stale PID file.

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

Last verified: 2026-10-21 against the `tmp/gpcli` snapshot
(`usr/local/bin/gpbup`, `gpbup2`, `lib/gpbup.sh`) plus a maintainer-supplied run
on a GridPane server.
