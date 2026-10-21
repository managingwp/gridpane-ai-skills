# Open Questions

Items the maintainer needs to decide or confirm. Per [AGENTS.md](AGENTS.md),
anything that cannot be verified against the GridPane Knowledge Base or
maintainer-supplied server output is recorded here rather than presented as fact.

## Unverified facts

Facts used in a skill that could not be traced to a source yet. Each entry names
the skill and reference file that mentions it, plus what would confirm it.

- **PHP-FPM defaults.** Default `pm` mode and `max_children` per pool vary by
  server size (the capture showed a server-level `pm.max_children:2` and a
  per-site `16`); a per-size reference would confirm the pattern
  (`gridpane-server-diagnostics/references/php-fpm.md`).
- **ModSecurity ruleset version.** Default paranoia level is `1` (capture +
  `lib/waf.sh`), but the exact CRS ruleset version on current stacks is unverified
  (`gridpane-security/references/waf.md`).
- **Maldet/ClamAV and vulnerability scanner availability** by default
  (`gridpane-security/references/compromise-first-response.md`).
- **`gp` flag coverage.** The complete flag list per area and accepted value
  ranges. The dispatcher/`lib` give the subcommands and many flags; the rest needs
  `gp … --help` output (`gridpane-gp-cli/references/command-reference.md`,
  `gridpane-tooling/references/gp-command-reference.md`).
- **Custom files under `/usr/local/bin`.** Whether an unrelated custom file
  survives a `gpupdate` run is unverified: `lib/update.sh` deploys with per-file
  `cp` plus a hardcoded cleanup block, but there is no confirmed guarantee
  (`gridpane-tooling/references/developing-tools.md`).
- **`gridpane::callback::app` payload contract.** The full set of app endpoints
  and required fields beyond `monitor::main`'s use is unverified
  (`gridpane-tooling/references/developing-tools.md`).
- **`/root/gridenv` key completeness.** The key tables come from a 2026-10-09
  capture plus KB-named keys; new keys appear as GridPane ships features.
  Undocumented keys (`gpfailsync-running`, `configs-update-processing`, most
  `promethean.env` flags) need confirmation
  (`gridpane-core/references/gridenv.md`).
- **Per-site env key completeness.** `cache-type` is now fully resolved
  (`redis`/`fastcgi`/`off` for Nginx; `redis-page`/`page-only`/`redis-only`/`off`
  for OLS). The rest of the `/var/www/{site.url}/logs/{site.url}.env` key set
  still grows as GridPane ships features
  (`gridpane-core/references/site-env.md`).
- **`redis.env` vs split Redis.** Coexistence is observed (all three files/flags
  and three Monit services); the split services read `/etc/redis/redis-page.conf`
  and `/etc/redis/redis-object.conf`. Whether the coexisting `redis.env` has any
  effect remains open (`gridpane-core/references/gridenv.md`).
- **MariaDB vs MySQL.** The captured stack is Percona and the scripts detect
  MariaDB (`lib/services.sh`), referencing `mysql.service`. Confirm the unit names
  on a MariaDB box (`gridpane-server-diagnostics/references/mysql.md`).

### OpenLiteSpeed

- **`gpols` command semantics.** The help lists
  `addon`/`build`/`delete`/`env`/`get`/`httpd`/`init`/`log`/`pma`/`redirect`/`site`/`stats`/`test`/`version`;
  which change state, and their blast radius, needs confirmation per command
  (`gridpane-core/references/ols.md`).
- **`.htaccess` auto-reload.** The KB says GridPane watches `.htaccess` and
  reloads OLS automatically; confirm this still applies on current stacks.
- **LSCache verification headers.** The KB refers to `HIT`/`MISS`; confirm the
  exact header names and values on a live OLS site.
- **OLS ModSecurity ruleset version.** The installer pins CRS `3.3.0`
  (`lib/ols/source/modsec.sh`); confirm what current servers run.

## Scope proposals

Changes to the skill set or safety model that need maintainer sign-off
(AGENTS.md ground rule 5).

- **License (decided).** MIT confirmed; `LICENSE` and `README.md` reflect it.
- **OpenLiteSpeed scope (decided).** Full OLS parity is in scope and tracked in
  the follow-up PGF `20261019-ols-parity`.
- **KB text snapshots (open).** Whether extracted KB text should be committed for
  offline agent use, or stay in the gitignored cache. Current behaviour: only the
  manifest is committed; raw JSON/HTML and extracted Markdown never are
  (`gridpane-tooling/references/docs.md`). Decide before any skill ships KB text.

## Needs real-server output

Details that should come from output captured on a real GridPane server before
they are treated as verified.

- `gp --help` / `gp site --help` / `gp stack --help` output, to confirm the exact
  subcommands and flags used in `gridpane-gp-cli` and
  `gridpane-tooling/references/gp-command-reference.md`.
- The **site**, **domain** and **system-user** list response field names. The
  endpoints themselves and the **server** summary fields are now verified from
  the API collection (`gridpane-api/references/endpoints.md`); the site CSV
  mapping in `gp-inventory.sh` stays best-effort until one live response is
  captured.
- API pagination scheme and rate-limit headers (the collection documents no
  pagination parameters).
- A directory listing of the per-site Nginx include location and confirmation of
  which GridPane-managed files `gp` regenerates.
