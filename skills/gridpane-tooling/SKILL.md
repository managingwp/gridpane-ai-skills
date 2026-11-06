---
name: gridpane-tooling
description: >-
  Use to build, deploy or debug custom tooling on a GridPane server:
  /usr/local/bin and lib scripts, the gp dispatcher, overwritten paths, monit
  hooks and logs.
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
- `references/docs.md` — the KB index (REST feed, plus a sitemap fallback),
  one-request search, text extraction, the changelog capture, and the CLI the
  KB refresh loop drives.

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

## Refreshing the KB

`references/docs.md` documents the KB CLI this skill ships. The loop that
refreshes the index and updates the skills that cite it is its own skill,
`gridpane-kb-refresh`; load that one for the procedure.

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
- **A `modified` timestamp edit is not a KB change.** `refresh` publishes the
  manifest only where the content hash or the title moved, so a page that only
  re-dated itself does not create a diff to act on.
- **`check` exit 3 is work, not failure.** It means the KB moved; the loop
  continues with `refresh`. Any other non-zero exit stops the loop.
- **`affected` is the only step that names the files to edit.** Do not hand-grep
  for KB URLs: the command already joins the diff to the `file:line` citations
  and reports a title-only change as well as a body change.
- **No KB prose in `skills/`.** The licence question is still open
  (`OPEN-QUESTIONS.md`); cite the URL and write the fact in our own words.

## Sources

- `gpcli` snapshot (maintainer-supplied, `tmp/gpcli`): `README.md`, `AGENTS.md`,
  `usr/local/bin/gp`, `usr/local/bin/gpupdate`, `usr/local/bin/lib/*.sh`.
- GP-CLI Quick Reference — https://gridpane.com/kb/gp-cli-quick-reference/
- Useful Commands for Managing GridPane Servers — https://gridpane.com/kb/useful-commands-for-managing-gridpane-servers/
- GridPane Logs — https://gridpane.com/kb/gridpane-logs-how-to-find-them-and-when-to-use-them/

Last verified: 2026-10-21
