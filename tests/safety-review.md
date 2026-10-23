# Safety review

Method and result of the Phase 6 safety review (AGENTS.md definition of done:
"Every command labelled; every [WRITE] has a rollback").

## Method

```bash
# Every file that contains a [WRITE] or [DESTRUCTIVE] label.
grep -rIl '\[WRITE\]\|\[DESTRUCTIVE\]' skills | sort

# Files with a [WRITE] but no mention of a rollback.
for f in $(grep -rIl '\[WRITE\]' skills); do
  grep -qi 'rollback' "$f" || echo "MISSING: $f"
done
```

The protocol itself lives in `gridpane-core/references/safety.md` and is required
by every skill body. Inline [WRITE] steps in the operational skills state effect,
blast radius, backup and rollback next to the command; the command references link
back to the protocol rather than repeating a rollback on every row.

## Result

- All bash/sh command blocks carry a [READ]/[WRITE]/[DESTRUCTIVE] label
  (enforced by `scripts/lint-skills.sh`).
- Every skill whose body or references contain [WRITE]/[DESTRUCTIVE] steps points
  at the safety protocol and states rollbacks for the concrete changes.
- The remaining reference-only files (`gridpane-gp-cli/references/command-reference.md`,
  `gridpane-api/references/endpoints.md`, `gridpane-core/references/gp-conventions.md`)
  carry an explicit pointer to the protocol: confirm, back up, and reverse with
  the reciprocal command.

## [DESTRUCTIVE] inventory

| Action | Where | Guard |
|---|---|---|
| Backup purge (`gpbup … -purge`, API purge endpoints) | gp-cli, api | Named by user; confirm twice; verify a usable backup remains |
| Staging → Live push | wordpress | Named by user; confirm twice; backup first |
| Site/database deletion | out of scope by default (safety.md rule 5) | Named by user only |

No command in the skills performs an unattended or fleet-wide destructive action.

## Backup-state [WRITE] actions

Missing-backup discovery in `gp-cli/references/missing-backups.md` distinguishes
storage reads from local metadata writes. Duplicacy `list` uses `[WRITE]` because
it can update cache/keyring state: confirm, preserve the existing `.duplicacy`
state (resolve pointer files), disable hooks with `-no-script`, and roll back
local state only when no job is using it. Querying from another site's existing
configuration does not authorize backup, restore, initialization or pruning.

These change GridPane's own backup bookkeeping, not site data. They are listed
separately because the rollback is "the next run recreates it", not a reciprocal
command.

| Action | Where | Guard | Rollback |
|---|---|---|---|
| Post the completion callback (`gp -function-run 'gpbup::callback::manual_backup_status …'`, `gp callback /backups/backup …`) | `gp-cli/references/backups.md` | Only when nothing is running (`tsp -l` has no `running` row, the site lock is free); `status=failed` unless a backup completed; the output carries the server key | None needed — it reports state, it does not change data |
| Remove a stale legacy PID lockfile `/opt/gridpane/backups/{site}-{storage}-{uuid}.pid` | `gp-cli/references/backups.md` | Only after the pid is dead and no `duplicacy` process exists for the site; never touch the `/run/gridpane/backups/` flock | The next run writes a new lockfile |
| Delete a stale `backup-*` cron while the storage toggle is off | `gp-cli/references/backups.md` | Toggle really is `OFF` in `backups.env` | Re-save the schedule in the panel, which recreates it |
