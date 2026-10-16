# `gp` architecture

How the GridPane CLI is assembled, so a tool can reuse it rather than duplicate
it. Source: the maintainer-supplied snapshot at `tmp/gpcli` (a mirror of the
scripts deployed to `/usr/local/bin`); line references are to that snapshot.

## Entry point and sourcing

`usr/local/bin/gp` is the entry point. On every run it:

1. sources `wp-completion.bash`, then **every** module in `lib/*.sh`
   (`gp:1-76`), and
2. calls `gp::main "$@"` and exits (`gp:2497-2499`).

Because all modules are sourced on every invocation, a syntax error in any one
module breaks the whole CLI, not just its own command. When you add a module,
validate it with `bash -n`.

`gp::main` (`gp:80-2496`) does the shared setup before dispatch:

- argument-count check and global setup (`gridpane::check::argnum`,
  `gridpane::setglobals`),
- `gridpane::logfunction "$@" | tee -a /var/log/gridpane.log` — every `gp` run is
  logged here (`gp:84`),
- ensures `/opt/gridpane/logs` exists (`gp:86-88`),
- `gridpane::validate` unless this is stage-two provisioning (`gp:105-107`),
- process-manager, bash-completion, crontab and MariaDB-plugin checks
  (`gp:109-114`),
- a **pre-dispatch** `case` (`gp:118-169`) that runs one-time syncs
  (`server::sync::stack`, `workers::parse::remote_toggle_logs`,
  `workers::update_server_os`) for `worker`/`backup`/`site` invocations,
- the **main dispatch** `case $1` (`gp:171-2495`).

Unknown commands print `Unknown GP CLI command... exiting...` and `exit 187`
(`gp:2491-2494`). Several subcommands use the same code.

## Dispatch table

`gp <area> …` maps to a module function (see
`references/gp-command-reference.md` for the full list). The first argument also
accepts a `-`-prefixed alias in most cases (e.g. `-site`, `-backup`).

## Wrappers

`gp<area>` scripts are thin shims that inject a subcommand and re-enter the
dispatcher:

```bash
#!/bin/bash
set -- "monit" "$@"
. /usr/local/bin/gp
```

`gpsite` guards against doubling the subcommand
(`[[ $1 != "site" ]] && set -- "site" "$@"`). Wrappers exist so cron jobs and
monit can call a function against the deployed copy, e.g. `gpworker` is
`set -- "worker" "-fifteen-min" "$@"`.

Standalone tools that are **not** wrappers include `gpupdate` (updater),
`gpcheck` (health), `gpgit` (git integration) and `gpmonit`/`gpmonitor`
(monit configuration and notification).

## Versioning and updates

- `usr/local/bin/gridpane.ver` carries `scripts-version:` — the marker the update
  system compares against (`gridpane.ver`).
- `gp update` execs `/usr/local/bin/gpupdate` (`gp:2469-2471`). `gpupdate`
  sources `lib/gridpane.sh`, `lib/monit.sh`, `lib/update.sh`, `lib/scan.sh` and
  fetches the packaged scripts/configs for the server's update branch. It
  **changes state** (fetches, `rsync`s, installs and removes files), so treat it
  as **[WRITE]**.
- `gpupdate` takes a **single-instance lock** in `/run/gridpane/gpupdate`
  (tmpfs, root-only `0700`). Modes: a scheduled run skips if another instance
  holds the lock; `daily` waits; `force` waits up to 60s then fails fast
  (`gpupdate` header).
- `gpscriptsbuild*` are GridPane's internal packaging/publish tools.

Implication for tooling: anything under `/usr/local/bin` (including `lib/`) is
replaced on update. See `references/developing-tools.md`.

## Monit integration

`/etc/monit/conf.d/programs` declares `check program` blocks that run scripts
under `/usr/local/bin/monit-scripts/` every cycle. On failure a check can
`exec "/usr/local/bin/gpmonitor …"`, which injects `monitor` and re-enters `gp`
→ `monitor::main` → `gridpane::notify::slack`, which POSTs a JSON body to the
GridPane API (which fans out to Slack). The full chain, with `file:line`
evidence, is in `tmp/gpcli/docs/monit-slack-notifications.md`.

## Gotchas for tool authors

- **`gp` ends with an unconditional `exit 0`** (`gp:2499`), so a called function's
  return code is normally lost. Some commands capture and re-exit it explicitly
  (e.g. `monit` at `gp:372-377`, `audit` at `gp:218-223`). A tool that shells out
  to `gp` cannot rely on `gp`'s exit status reflecting the inner function.
- **`gp` is root-oriented.** It sets ACLs on `/bin` and `/dev` (`gp:77-78`) and
  writes to `/opt/gridpane`, `/var/log/gridpane.log` and `/root`. Do not call it
  as a site user.
- **`gp wp` runs WP-CLI as the site system user**; `gp wp all-sites …` runs it
  across every site (`gp:2460-2467`).
- **Everything is logged.** Assume your invocation is recorded in
  `/var/log/gridpane.log`.

## Sources

- `tmp/gpcli/usr/local/bin/gp` (line references above).
- `tmp/gpcli/usr/local/bin/gpupdate` (update model and lock).
- `tmp/gpcli/README.md` (layout, wrappers, modules, `gridpane.ver`).
- `tmp/gpcli/docs/monit-slack-notifications.md` (notification chain).

Last verified: 2026-10-14
