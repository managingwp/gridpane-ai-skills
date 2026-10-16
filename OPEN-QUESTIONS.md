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
- **`redis.env` vs split Redis.** Coexistence is observed (all three files/flags
  and three Monit services); the split services read `/etc/redis/redis-page.conf`
  and `/etc/redis/redis-object.conf`. Whether the coexisting `redis.env` has any
  effect remains open (`gridpane-core/references/gridenv.md`).
- **MariaDB vs MySQL.** The captured stack is Percona and the scripts detect
  MariaDB (`lib/services.sh`), referencing `mysql.service`. Confirm the unit names
  on a MariaDB box (`gridpane-server-diagnostics/references/mysql.md`).

## Scope proposals

Changes to the skill set or safety model that need maintainer sign-off
(AGENTS.md ground rule 5).

- **License.** `LICENSE` currently carries MIT, carried over from README.md
  ("MIT (proposed; confirm before first release)"). Confirm MIT or replace it
  before the first public release.
- **OpenLiteSpeed scope.** Nginx is documented first; OLS is covered where it
  differs (paths, WAF, IP deny) but not exhaustively. Decide whether full OLS
  parity is in scope for a future release or explicitly out of scope.

## Needs real-server output

Details that should come from output captured on a real GridPane server before
they are treated as verified.

- `gp --help` / `gp site --help` / `gp stack --help` output, to confirm the exact
  subcommands and flags used in `gridpane-gp-cli` and
  `gridpane-tooling/references/gp-command-reference.md`.
- The **servers** and **sites** list endpoints and their response field names for
  the GridPane REST API. `gridpane-api/references/endpoints.md` only verifies the
  base URL, `Authorization: Bearer` auth and the backup endpoints; the inventory
  script (`scripts/gp-inventory.sh`) therefore requires the list paths to be
  supplied and uses a best-effort CSV mapping. Confirm from the Postman
  collection: https://documenter.getpostman.com/view/13664964/TVssjU7Z
- API pagination scheme and rate-limit headers.
- A directory listing of the per-site Nginx include location and confirmation of
  which GridPane-managed files `gp` regenerates.
- The per-site state file `/var/www/{site.url}/logs/{site.url}.env` is partly
  verified (maintainer capture 2026-10-09): `cache-type` (observed `redis`),
  `redis-object-cache`, `ngx-redis-cache-valid`, `nginx-caching-ttl` and the PHP
  keys are confirmed. Still open: the exact `cache-type` values for FastCGI and
  caching-off (`gridpane-core/references/site-env.md`,
  `gridpane-wordpress/references/caching.md`).
- **GridPane changelog capture.** `roadmap.gridpane.com/changelog` is a
  JavaScript SPA backed by Upvoty; plain `curl` returns only the app shell.
  Capturing it needs the Upvoty board/API identifier, an RSS/export, or a
  headless browser (`gridpane-tooling/references/docs.md`).
