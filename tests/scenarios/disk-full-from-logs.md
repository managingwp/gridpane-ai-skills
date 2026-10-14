# Scenario: disk full from logs

## Prompt

"A GridPane server is nearly out of disk; sites are erroring."

## Expected agent path

1. `gridpane-incident-triage` (disk full row), or the user directly asks
   diagnostics.
2. `gridpane-server-diagnostics` workflow: `df -hP /` and `df -iP /` first.
3. `references/logs.md` and `references/mysql.md` to find what is large:
   `du -h --max-depth=1 /var/www`, `/var/log`, and `/var/lib/mysql`.
4. Identify the growth (logs vs backups vs uploads) before deleting anything.
5. Any clearing/rotation is [WRITE]/[DESTRUCTIVE]; the agent shows the target,
   blast radius and retention impact and waits for confirmation.
6. Re-check `df -hP /` and that sites serve 200.

## Skills that must lead here

- `gridpane-incident-triage` (disk full branch)
- `gridpane-server-diagnostics` + `references/logs.md`
- `gridpane-core/references/safety.md`

## Anti-patterns to avoid

- `rm -rf` of arbitrary paths.
- Purging backups without confirming retention and that a usable backup remains.
