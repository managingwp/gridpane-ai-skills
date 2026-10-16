# gp conventions

How the GridPane CLI (`gp`) is structured, how to discover commands, and which
commands read versus change state.

## Shape of a command

```
gp <area> <target> <flag> [value...]
```

Areas seen in the KB:

| Area | What it operates on | Examples |
|---|---|---|
| `gp site` | A single site, or `all-sites` | `gp site example.com -suspend` |
| `gp stack` | A server-level stack component | `gp stack nginx worker -connections 4096` |
| `gp ngx` | The Nginx service | `gp ngx -reload` |
| `gp php` | A PHP-FPM service for a version | `gp php 8.1 -restart` |
| `gp mysql` | MySQL/MariaDB service | `gp mysql -restart` |
| `gp redis` | Redis service | `gp redis -status` |
| `gp wp` | WP-CLI as the site system user | `gp wp example.com plugin list` |
| `gp fix` | Self-help repairs | `gp fix cached example.com` |
| `gp server` | Server-wide toggles | `gp server -tmp-noexec enable` |
| `gpmonit` | Monit thresholds | `gpmonit redis -mem-high-mb 2000` |
| `gpbup` / `gpbup2` | Backups (v2) | `gpbup2 example.com -local-single-site` |

Backups also use `gpbup`; there is a separate `gpbup2` for v2 local backups.

## Discover before you run

Do not guess flags. Ask the tool:

```bash
# [READ] Top-level and per-area help.
gp --help
gp site --help
gp stack --help
```

Also useful for orientation:

```bash
# [WRITE] Refresh GridPane's own scripts. Blast radius: whole server (it
# replaces /usr/local/bin and applies config updates). Rollback: re-run after
# pinning to the previous version; there is no per-file undo. Confirm first.
gpupdate
```

`gpupdate` refreshes GridPane's own scripts **and changes state**: it fetches the
packaged scripts/configs for the update branch, `rsync`s and installs them, and
removes superseded files (`lib/update.sh`). Treat it as **[WRITE]** under the
safety protocol, not as a passive refresh.

## Reading the activity log

`/var/log/gridpane.log` records `gp`/GridPane actions. Use it to see what changed
and when, which is often faster than guessing:

```bash
# [READ] Last 100 GridPane actions.
tail -n 100 /var/log/gridpane.log
```

## Informational vs mutating

Group by intent, not by name:

- **Informational ([READ]):** `-status` flags (`gp ngx -status`), `gp --help`,
  `gp mysql login`/`get-pass` (these reveal credentials — never print them into
  a transcript), listing commands.
- **Mutating ([WRITE]):** `-start`/`-stop`/`-reload`/`-restart`, `-on`/`-off`
  toggles (`-7g-on`, `-fastcgi-cache`, `-wp-debug-on`), `-switch-php`,
  `gp fix cached`.
- **Destructive ([DESTRUCTIVE]):** site suspend is reversible and is [WRITE];
  but deleting a site, dropping a database, overwriting production from staging,
  and `{storage} -purge` of backups are [DESTRUCTIVE].

## Scope rules

Commands labelled **[WRITE]** or **[DESTRUCTIVE]** here still follow
`references/safety.md`: propose with effect, blast radius, backup and rollback,
and wait for confirmation. Informational commands are [READ] and may run freely.

- `gp site {site.url} ...` → one site.
- `gp site all-sites ...` (e.g. `sync-php-settings`) → **every site on the
  server**. Server-wide [WRITE].
- `gp fix cached` **without** a site URL → clears caches for **every site on the
  server**. `gp fix cached {site.url}` scopes it to one site.
- `gp stack ...` → server-wide: it edits the stack config, not a single site.

## Gotchas

- Some `gp` commands reload a service implicitly after changing a setting. When
  you chain several, pass the documented `-no-reload` flag where it exists so you
  reload once, not once per command.
- `gp site {site.url} ...` commands that write settings regenerate the site's
  managed config. That is expected; do not hand-edit those files (see
  `paths.md`).
- Prefer the control-panel toggle for domain routing and caching where the KB
  says so; the CLI equivalents exist but the panel is the documented path.

## Unverified

- The complete flag list for each area. `gp --help` output from a real server is
  needed to confirm every subcommand before they are presented as current.
