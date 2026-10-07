# Safety protocol

GridPane servers are usually live production hosting for paying clients. One
wrong command can take down every site on the box. This file is the contract the
agent follows before it changes anything.

## Command labels

Every shell, `gp`, WP-CLI or API call carries exactly one label.

| Label | Meaning | Agent behaviour |
|---|---|---|
| **[READ]** | No state change | Run freely |
| **[WRITE]** | Changes config, cache, service state or data; reversible | Show the command, effect, blast radius and rollback; wait for explicit confirmation; back up first |
| **[DESTRUCTIVE]** | Hard or impossible to reverse | Run only when the user names this exact action; confirm twice; verify a backup exists |

Clearing cache is [WRITE] (reversible, but it has an effect). Reloading or
restarting a service is [WRITE]. Never mix [READ] and [WRITE] commands into a
single pasted block.

## The rules

1. **Diagnose first.** Read-only commands (status, logs, config reads, `gp` info
   commands) run freely. Do not change config before you know the cause; that
   destroys the evidence and can mask the real fault.
2. **Propose, then confirm.** Before any change, present the confirmation block
   below and wait for a literal "yes".
3. **Back up before editing.** Copy any config file to
   `<file>.bak-<timestamp>` before it changes.
4. **Validate before reload.** Run `nginx -t` (or the OLS equivalent) before any
   reload. A failed test means no reload, full stop.
5. **Never by default:** deleting sites, dropping databases, `rm -rf`, editing
   GridPane-managed files that `gp` regenerates, rebooting, or bulk actions
   across the fleet. These require the user to name the action explicitly.
6. **Prefer `gp` over hand edits.** When GridPane provides a command, use it.
   Hand-edited managed files get overwritten (see `paths.md`).

## Confirmation template

Use this block verbatim before running a [WRITE] command. Fill in real values;
do not leave placeholders.

```
PROPOSED CHANGE [WRITE]
Command:      <exact command(s) to run>
Effect:       <what this changes and why>
Blast radius: site example.com only | all sites on server | fleet
Backup:       <file copied to .bak-<timestamp>, or "none applicable">
Rollback:     <exact command(s) to reverse it>
Proceed? (yes/no)
```

For a [DESTRUCTIVE] command, state plainly that it cannot be undone and require
the user to name the action themselves before you present the block, then get
confirmation twice and confirm a backup exists.

## Backing up a config file

```bash
# [READ] Record what you are about to change (also serves as the rollback copy).
cp -a /path/to/file.conf /path/to/file.conf.bak-$(date +%Y%m%d%H%M%S)
```

The copy itself is non-destructive, but do it as part of a [WRITE] proposal, not
silently.

## Reload vs restart

Prefer a reload (`gp ngx -reload`, `gp php {version} -reload`) over a restart.
A reload is graceful; a restart drops in-flight requests. Both are [WRITE].

## When something goes wrong

- If validation fails after an edit, restore the `.bak-<timestamp>` copy and
  reload the last known-good config; do not push through a broken change.
- If a change affects more than the intended site, stop and report the blast
  radius before doing anything else, so the user decides the next step.
