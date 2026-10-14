# Open Questions

Items the maintainer needs to decide or confirm. Per [AGENTS.md](AGENTS.md),
anything that cannot be verified against the GridPane Knowledge Base or
maintainer-supplied server output is recorded here rather than presented as fact.

## Unverified facts

Facts used in a skill that could not be traced to a source yet. Each entry names
the skill and reference file that mentions it, plus what would confirm it.

- **MySQL slow query log path.** The logs KB page gives
  `/var/log/mysql/error.log` for the slow log in one place but shows
  `cat /var/log/mysql/slow.log` elsewhere. Skills cite `/var/log/mysql/slow.log`
  and note the ambiguity (`gridpane-core/references/paths.md`,
  `gridpane-server-diagnostics/references/mysql.md`). Confirm on a real server.
- **MariaDB vs MySQL.** Whether current stacks default to MariaDB, and the
  resulting `systemctl` unit names, is unverified.
- **PHP-FPM defaults.** Default `pm` mode and `max_children` per pool
  (`gridpane-server-diagnostics/references/php-fpm.md`).
- **`/tmp` mount details.** Confirmed noexec on Ubuntu 22.04+; the exact mount
  unit/options are unverified.
- **Nginx PHP-context include name.** The exact `*-php-context.conf` include
  filename used inside GridPane's PHP `location`, used by the rate-limit snippet
  (`gridpane-nginx-config/references/snippets.md`).
- **Cloudflare real-IP mechanism.** The exact headers/directives GridPane uses for
  real-IP restoration (`gridpane-security/references/cloudflare.md`).
- **ModSecurity defaults.** Ruleset version and default paranoia level
  (`gridpane-security/references/waf.md`).
- **Maldet/ClamAV and vulnerability scanner availability** by default
  (`gridpane-security/references/compromise-first-response.md`).
- **`gp` flag coverage.** The complete flag list per area and accepted value
  ranges (`gridpane-gp-cli/references/command-reference.md`).
- **`gpupdate` semantics.** Whether it is purely a refresh or can change state.
- **`/root/gridenv` write protection.** Reported (third-party) as `chattr +i`
  immutable. Evidence from the `gpcli` snapshot: `gridpane::conf_write` runs
  `chattr -i` on the target env file before writing (`lib/gridpane.sh:1059`),
  which strongly implies the immutable bit is set. Confirm on a real server
  (`lsattr /root/gridenv`). (`gridpane-core/references/gridenv.md`,
  `gridpane-tooling/references/developing-tools.md`)
- **Custom files under `/usr/local/bin`.** Whether an unrelated custom file
  survives a `gpupdate` run is unverified: `lib/update.sh` deploys with per-file
  `cp` plus a hardcoded cleanup block, but there is no confirmed guarantee.
  `gridpane-tooling/references/developing-tools.md` advises placing tooling
  elsewhere.
- **GridPane changelog capture.** `roadmap.gridpane.com/changelog` is a
  JavaScript SPA backed by Upvoty; plain `curl` returns only the app shell.
  Capturing it needs the Upvoty board/API identifier, an RSS/export, or a
  headless browser. Deferred until the maintainer supplies the details
  (`gridpane-tooling/references/docs.md`).
- **`gridpane::callback::app` payload contract.** The full set of app endpoints
  and required fields beyond `monitor::main`'s use is unverified
  (`gridpane-tooling/references/developing-tools.md`).
- **`/root/gridenv` key completeness.** The key tables come from a
  2026-10-09 capture plus KB-named keys; new keys appear as GridPane ships
  features. Undocumented keys (`gpfailsync-running`,
  `configs-update-processing`, most `promethean.env` flags) need confirmation.
- **`redis.env` vs split `redis-page.env`/`redis-object.env`.** Coexistence is now
  observed on a real server (2026-10-09): all three files, all three
  `promethean.env` flags and Monit thresholds for all three services. What remains
  unverified is which config the split services actually read, and whether the
  coexisting `redis.env` has any effect. (`gridpane-core/references/gridenv.md`)

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
  subcommands and flags used in `gridpane-gp-cli`.
- The **servers** and **sites** list endpoints and their response field names for
  the GridPane REST API. `gridpane-api/references/endpoints.md` only verifies the
  base URL, `Authorization: Bearer` auth and the backup endpoints; the inventory
  script (`scripts/gp-inventory.sh`) therefore requires the list paths to be
  supplied and uses a best-effort CSV mapping. Confirm from the Postman
  collection: https://documenter.getpostman.com/view/13664964/TVssjU7Z
- API pagination scheme and rate-limit headers.
- A directory listing of the per-site Nginx include location and confirmation of
  which GridPane-managed files `gp` regenerates.
- The per-site state file `/var/www/{site.url}/logs/{site.url}.env` is now partly
  verified (maintainer capture 2026-10-09): `cache-type` (observed `redis`),
  `redis-object-cache`, `ngx-redis-cache-valid`, `nginx-caching-ttl` and the PHP
  keys are confirmed. Still open: the exact `cache-type` values for FastCGI and
  caching-off, and the complete key set.
  (`gridpane-core/references/site-env.md`,
  `gridpane-wordpress/references/caching.md`)
