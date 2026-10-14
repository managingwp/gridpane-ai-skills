# Developing tools on GridPane servers

Patterns for adding your own tooling to a GridPane-managed server without
fighting the platform. Source: the maintainer-supplied snapshot at `tmp/gpcli`
(line references are to that snapshot).

## Golden rules

1. **Never hand-edit GridPane's deployed scripts.** `/usr/local/bin` (including
   `lib/`) is GridPane's; `gpupdate` deploys over it and the file is not yours to
   change. Treat the whole tree as read-only.
2. **Put custom tooling outside `/usr/local/bin`.** Use a directory GridPane
   does not manage (for example `/usr/local/sbin`, `/opt/<your-tool>`, or
   `/root/<your-tool>`), and re-deploy after updates if you must place anything
   in a managed tree.
3. **Read state from the env files, not by guessing.** Server state is
   `/root/gridenv/*.env`; per-site state is
   `/var/www/{site.url}/logs/{site.url}.env` (see
   `gridpane-core/references/gridenv.md` and `site-env.md`).
4. **Use `gp` for changes.** It regenerates the managed config for you; a hand
   edit to a managed file is undone on the next `gp` run.
5. **Log the way GridPane logs.** Append to `/var/log/gridpane.log` and use
   syslog (`logger`) for service events; redact secrets.

## Where custom tooling can live

| Location | Survives `gpupdate`? | Notes |
|---|---|---|
| `/usr/local/bin`, `/usr/local/bin/lib` | Only if the name is not a GridPane script; **unsupported** | GridPane copies its files here; a same-named file is overwritten. |
| `/usr/local/sbin` | Yes | Not managed by GridPane; on `PATH` for root. |
| `/opt/<your-tool>` | Yes | Good for a tool with its own files; `/opt/gridpane` is GridPane's, use a different subdir. |
| `/root/<your-tool>` | Yes | Root-only. |
| `/etc/nginx/extra.d/_custom/`, `/var/www/{site.url}/nginx/` | Yes | Supported config include locations (`gridpane-core/references/paths.md`). |

Do not rely on `/usr/local/bin` as a durable home. `lib/update.sh` deploys with
per-file `cp` and a hardcoded cleanup block; the exact survival of an unrelated
custom file is **unverified** (see below).

## Configuration I/O

GridPane stores state as `key:value` lines in env files. The CLI reads and writes
them through `gridpane::conf_read` / `gridpane::conf_write` /
`gridpane::conf_delete` (`lib/gridpane.sh:835,973,1132`), which:

- resolve the server files under `/root/gridenv/` (`promethean.env`, `nginx.env`,
  `mysql.env`, `redis*.env`, `monit.env`, `php{version}.env`, `active-sites.env`,
  …) and the per-site file at `/var/www/{site}/logs/{site}.env`
  (`lib/gridpane.sh:1004`),
- run `chattr -i` on the file before writing — confirming `/root/gridenv` is
  marked immutable (`lib/gridpane.sh:1059`), and
- create the file if missing.

A tool that only *reads* should not call `conf_write`; parse the env file
directly. A tool that *writes* should go through `conf_write` so the immutable
flag and permissions are handled, and should treat the change as a [WRITE] under
the `gridpane-core` safety protocol.

## Logging

`gp::main` pipes every invocation through
`gridpane::logfunction | tee -a /var/log/gridpane.log` (`gp:84`). `logfunction`
(`lib/gridpane.sh:762`) normalises wrapper names to `gp`, records the timestamp,
PID and arguments, and passes the arguments through
`gridpane::redact_sensitive_args` (`lib/gridpane.sh:711`) so secrets are not
written to the log. Follow the same idea: log the action, redact credentials.

## Callbacks and notifications

Two mechanisms talk back to GridPane's app:

- `gridpane::callback::app` (`lib/gridpane.sh:2206`) POSTs a JSON payload to an
  app endpoint (it ensures `jo` is installed to build the JSON). The `--checked`
  form returns non-zero on HTTP errors with bounded retries.
- `gridpane::notify::slack` (`lib/gridpane.sh:2416`) POSTs a JSON body to
  `https://${GPURL}/api/wsod/completed?${token_type}=${gridpanetoken}`; the app
  fans this out to Slack.

Both read `GPURL`, `token_type`, `gridpanetoken`, `serverIP` and `server_id` from
the globals set in `gridpane::setglobals` (`lib/gridpane.sh:202`). A tool that
needs to notify should reuse these rather than inventing its own webhook.

## Monit integration (worked example)

A monit check that should notify is three files:

1. **The check script** under `/usr/local/bin/monit-scripts/` (e.g.
   `openlitespeed_conf_test`) exits non-zero on failure.
2. **The monit program** in `/etc/monit/conf.d/programs` runs it and, on failure,
   execs the notifier:

   ```
   check program openlitespeed_conf_check
     with path "/usr/local/bin/monit-scripts/openlitespeed_conf_test"
     every 1 cycles
     if status != 0 then exec "/usr/local/bin/gpmonitor OPENLITESPEED CONF_SYNTAX error" AND repeat every 1 cycles
   ```

3. **The notifier** `gpmonitor` injects `monitor` and re-enters `gp`
   (`set -- "monitor" "$@"; . /usr/local/bin/gp`), so `monitor::main` maps the
   service/aspect to a title, details and event type and calls
   `gridpane::notify::slack`.

The full chain, with `file:line` evidence, is in
`tmp/gpcli/docs/monit-slack-notifications.md`. To add your own check, add a
script under `monit-scripts/` and a `check program` block — but remember those
live in GridPane-managed trees, so coordinate with the platform rather than
hand-editing them in place.

## Testing and lint

Follow GridPane's own bar for shell code:

```bash
# [READ] Syntax-check a script.
bash -n /path/to/tool.sh
```

```bash
# [READ] Lint it the way GridPane's CI does.
shellcheck --exclude=SC2145,SC2068,SC2261 --severity=error /path/to/tool.sh
```

## Deployment and versioning

`gpupdate` fetches the packaged scripts and applies them
(`references/gp-architecture.md`). The deployed version marker is
`/usr/local/bin/gridpane.ver`. If your tool depends on a specific `gp` version,
check that marker rather than assuming.

## Unverified

- Whether an unrelated custom file placed in `/usr/local/bin` survives a
  `gpupdate` run. `lib/update.sh` uses per-file `cp` plus a hardcoded cleanup
  block, but the exact behaviour is not confirmed; do not rely on it.
- Whether `/root/gridenv` is always `chattr +i` on every stack. `conf_write` runs
  `chattr -i` before writing, which strongly implies it.
- The full payload contract of `gridpane::callback::app` endpoints beyond what
  `monitor::main` uses.

## Sources

- `tmp/gpcli/usr/local/bin/lib/gridpane.sh` (`conf_read`/`conf_write`/`conf_delete`,
  `logfunction`, `redact_sensitive_args`, `callback::app`, `notify::slack`,
  `setglobals`).
- `tmp/gpcli/usr/local/bin/lib/update.sh` (deploy mechanism).
- `tmp/gpcli/usr/local/bin/gp` (logging pipeline, dispatch).
- `tmp/gpcli/etc/monit/conf.d/programs` (monit program shape).
- `tmp/gpcli/docs/monit-slack-notifications.md` (notification chain).

Last verified: 2026-10-14
