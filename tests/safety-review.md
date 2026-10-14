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
