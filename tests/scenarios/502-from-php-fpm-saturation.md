# Scenario: 502 from PHP-FPM saturation

## Prompt

"example.com on our GridPane server keeps returning 502 Bad Gateway under load."

## Expected agent path

1. `gridpane-incident-triage` is the entry point (site down with 502).
2. It runs the universal first checks (load/memory/disk, recent GridPane
   activity, site error log) and then the 502 row.
3. Hand off to `gridpane-server-diagnostics`, specifically
   `references/php-fpm.md`, to check pool worker counts and `max_children`
   warnings in `/var/log/php/{version}/fpm.log`, and `free -h` for swap.
4. If one pool is saturated, propose raising `max_children` for one site:
   `gp stack php -site-pm-max-children … example.com` ([WRITE]) with the
   confirmation block and rollback.
5. Verify with `curl -I` returning 200/30x and no fresh `max_children` warnings.

## Skills that must lead here

- `gridpane-incident-triage` (routing + 502 branch)
- `gridpane-server-diagnostics` + `references/php-fpm.md`
- `gridpane-core/references/safety.md` (confirmation + rollback)

## Anti-patterns to avoid

- Restarting PHP before capturing the FPM log and processlist (destroys
  evidence).
- Raising `max_children` on a swapping box without checking RAM first.
