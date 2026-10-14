---
name: gridpane-tooling
description: >-
  Use when building, deploying, debugging or reviewing custom tooling on a
  GridPane-managed server: bash or PHP scripts, gp wrappers, monit checks, or
  tools that read GridPane config and logs. Covers the /usr/local/bin + lib/
  script architecture, the gp dispatcher and its wrappers, where configs and logs
  live, which paths GridPane overwrites on update, and how to hook into monit and
  GridPane notifications. Do not use for writing a WordPress plugin or theme
  (see gridpane-wordpress), for generic bash/PHP questions with no GridPane
  context, or before loading gridpane-core for the safety model and paths.
---

# gridpane-tooling

How GridPane's own server tooling is built, and how to add your own alongside it
without being overwritten. GridPane deploys a set of Bash scripts to
`/usr/local/bin` (with the implementation in `lib/`) and drives them from the
`gp` dispatcher; a tool that runs on a GridPane box should read the same config
and log locations and follow the same conventions.

Load `gridpane-core` first for the safety model, the operational path map and
`gp` conventions. This skill is the *developer* view: what the scripts are, where
their files and logs live, and how to extend them safely.

Read the reference that matches the task:

- `references/server-layout.md` — where GridPane's tooling, state, config and
  logs live, and which paths updates overwrite.
- `references/gp-architecture.md` — how `gp` is structured (dispatcher,
  wrappers, `lib/` modules, versioning, updates).
- `references/gp-command-reference.md` — the `gp` command tree, by area.
- `references/developing-tools.md` — patterns for adding tooling: placement,
  config I/O, logging, callbacks and monit integration.
- `references/docs.md` — the KB docs manifest and the (deferred) changelog
  capture.

## Prerequisites

- Root (or sudo) over SSH to inspect a live server; reading this skill needs no
  access.
- `gridpane-core` loaded.
- Confirm the stack (`gp ngx -status` for Nginx, `gpols -status` for
  OpenLiteSpeed) before assuming a path.
- Never edit GridPane's deployed scripts or managed config by hand; see
  `references/developing-tools.md` for where custom tooling may live.

## Workflow

1. **Identify the target.** One server or many? Which stack (Nginx/OLS)? Is the
   tool read-only or does it change state?
2. **Read the architecture before writing code.** `gp` sources every `lib/*.sh`
   then dispatches on its first argument; wrappers such as `gpsite` re-enter
   `gp`. Reusing an existing function is safer than duplicating logic.
3. **Find the right location.** Config lives under `/root/gridenv` (server) and
   `/var/www/{site.url}/logs/{site.url}.env` (per site); logs under
   `/var/log/gridpane.log`, `/opt/gridpane/*.log` and
   `/var/www/{site.url}/logs/`. See `references/server-layout.md`.
4. **Check whether the path is managed.** `/usr/local/bin` (including `lib/`) is
   replaced by `gpupdate`. Put custom tooling where an update will not remove it,
   or re-deploy it after updates.
5. **Develop read-only first.** Diagnose and log before changing anything.
   Changing server config is a [WRITE] and needs the `gridpane-core` protocol.
6. **Validate and confirm.** Run `bash -n` and `shellcheck` on scripts; confirm
   behaviour with an observable check, not a feeling.

## Commands

Inspect the tooling without changing anything:

```bash
# [READ] What GridPane scripts are deployed and where the implementation lives.
ls -la /usr/local/bin/gp /usr/local/bin/lib
```

```bash
# [READ] The deployed scripts version (the update system compares this).
tail -n 3 /usr/local/bin/gridpane.ver
```

```bash
# [READ] Discover gp commands from the dispatcher rather than guessing.
gp --help
gp site --help
gp stack --help
```

```bash
# [READ] Recent GridPane tooling activity.
tail -n 100 /var/log/gridpane.log
```

## Verify

This skill changes nothing, so there is no fix to verify. When reviewing a tool,
confirm: it reads the correct config/log path for the stack, it does not write to
a managed file, `bash -n`/`shellcheck` pass, and its effect is observable.

## Rollback

Not applicable to the reference itself. Any tool that writes must carry its own
backup and rollback and follow the `gridpane-core` safety protocol.

## Gotchas

- **`gpupdate` replaces `/usr/local/bin` and `lib/`.** Hand edits there are
  overwritten. See `references/developing-tools.md`.
- **`gp` sources every `lib/*.sh` on every run.** A broken module breaks the
  whole CLI, not just its own command.
- **Unknown commands exit `187`.** A typo returns that code rather than a
  message; check `gp --help`.
- **Secrets live on disk.** `/root/gridcreds/` and `/root/gridenv` hold
  credentials; never print or commit them.
- **Nginx vs OLS.** Config and log paths differ; confirm the stack first.

## Sources

- `gpcli` snapshot (maintainer-supplied, `tmp/gpcli`): `README.md`, `AGENTS.md`,
  `usr/local/bin/gp`, `usr/local/bin/gpupdate`, `usr/local/bin/lib/*.sh`.
- GP-CLI Quick Reference — https://gridpane.com/kb/gp-cli-quick-reference/
- Useful Commands for Managing GridPane Servers — https://gridpane.com/kb/useful-commands-for-managing-gridpane-servers/
- GridPane Logs — https://gridpane.com/kb/gridpane-logs-how-to-find-them-and-when-to-use-them/

Last verified: 2026-10-14
