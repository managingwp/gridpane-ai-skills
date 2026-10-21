# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- `scripts/gridpane-kb-docs.sh`: one command to scrape and manage the KB cache.
  `status` reports how many articles are ingested (the committed manifest),
  cached (the newest snapshot) and extracted, plus the drift between them, the
  newest article and the snapshot list — without touching the network, and with
  `--json` and an optional one-request `--remote` check; `check` answers "did
  anything change?" in one request (exit 3 when it did); `refresh` probes,
  indexes a new dated snapshot, diffs it against the previous one, and publishes
  `references/docs-manifest.json` only when its content changed. `list` browses
  the cached articles, `search` queries the live KB, `diff` compares snapshots,
  `extract` converts a body to text or markdown, and `prune` removes old
  snapshots (dry run unless `--yes`).
- `gridpane-tooling/scripts/scrape-docs.sh --search`: one-request KB lookup
  against the WordPress REST feed (`--json` for the raw array); a query refuses
  `--out`/`--offline` and reports `no matches` without failing.
- `scrape-docs.sh --slug/--all --format text|markdown`: convert a cached KB body
  to text in the gitignored cache, with pandoc when available and a built-in
  awk/sed converter otherwise (no inline CSS, entities decoded once).

### Changed

- Install path: the repository is a `npx skills` package. `npx skills add
  managingwp/gridpane-ai-skills` installs the nine production skills into an
  agent (Claude Code, Codex, OpenCode, …), with `update`/`remove`/`list` handled
  by the CLI; the README leads with it and keeps `scripts/install.sh` as the
  offline fallback.
- `skills/_template`: the scaffold now carries `metadata.internal: true`, so the
  CLI no longer offers it as an installable `gridpane-example` skill.
  `scripts/lint-skills.sh` requires the marker on `_`-prefixed folders and
  rejects it on real skills; `scripts/install.sh` reports the number it actually
  installed.
- `gridpane-tooling/scripts/scrape-docs.sh` + `references/docs-manifest.json`:
  index the KB from the public WordPress REST feed for the `kb` post type — four
  requests for 387 posts, `X-WP-Total` cross-checked — instead of 387 page
  fetches. Adds `--source api|sitemap`, `--since` (`modified_after` incremental
  refresh), category names from `kbcategories`, and a
  `{source, fetched_at, count, entries}` manifest envelope with per-entry
  `modified`/`categories`/`source`.
- `scrape-docs.sh` dates: the manifest `modified` is now UTC (`modified_gmt`)
  with a new `published` from `date_gmt` and `schema: 2`, because the REST
  `modified` field is site-local (UTC-4). Adds `--probe` (one request returns
  the newest `modified_gmt`; the site sends no `Last-Modified`/`ETag`) and
  `--since-last`; search prints UTC dates too.
- `scrape-docs.sh` snapshots and guards: every live run writes
  `out/gridpane-docs-cache/<YYYY-MM-DD>[-N]/` and points `latest` at it, never
  overwriting an existing snapshot. The request delay defaults to 10 s and is a
  floor for live runs (`--allow-fast` for fixtures only). Aborts on a >10% entry
  count drop (`--force`), an `X-WP-Total` mismatch (`--partial`), a non-array or
  >8 MB response, or a concurrent run (`flock`). `--diff` reports
  added/removed/changed/title-only between two snapshots.
- `AGENTS.md` and `gridpane-tooling/references/docs.md`: add the "Refreshing KB
  facts" workflow, the snapshot/guard reference and the five-surface date model
  (which value is UTC and which is site-local).
- `gridpane-tooling/references/docs.md` and
  `gridpane-core/references/sources.md`: document the REST endpoints, the
  manifest schema, search and extraction, and the measured request/payload
  numbers; record the KB text-snapshot policy question in `OPEN-QUESTIONS.md`.

## v0.3.0 - 2026-10-20

### Changed

- Resolve the snapshot-verifiable items in `OPEN-QUESTIONS.md`: the Nginx
  PHP-context include (`/etc/nginx/extra.d/*-php-context.conf`), the `/tmp`
  fstab line, the MySQL slow-log path (`/var/log/mysql/slow.log`), the split
  Redis config paths, `gpupdate` as [WRITE], the ModSecurity paranoia default,
  and `/root/gridenv` `chattr +i`.
- `gridpane-tooling/references/gp-command-reference.md`: add the dispatcher's
  `gp site` flag set, grouped, and reconcile the KB reference's 117 flags against
  the dispatcher (all present).
- `gridpane-security/references/cloudflare.md`: document the verified real-IP
  chain (`gridpane-realip.conf` → `*cloudflare-realip.conf`, `CF-Connecting-IP`,
  ranges staged at `/opt/gridpane/cf_*.ip`).
- `gridpane-tooling/scripts/scrape-changelog.sh` +
  `references/changelog-manifest.json`: capture the GridPane changelog from its
  public Upvoty JSON API (curl + jq, no browser), with an offline test; the
  changelog is no longer deferred.
- `gridpane-api`: verify the endpoint catalogue and server summary fields from
  the Postman collection, default `gp-inventory.sh` to `/server?summary=true`
  and `/site`, and add a `servers.csv` export; update the fixtures and tests.
- `gridpane-core/references/site-env.md`: resolve the `cache-type` values from
  the deployed scripts — `redis`/`fastcgi`/`off` for Nginx and
  `redis-page`/`page-only`/`redis-only`/`off` for OpenLiteSpeed — and note them
  in `gridpane-wordpress/references/caching.md`.
- License confirmed as MIT (README wording updated); full OpenLiteSpeed parity
  accepted as in scope and tracked in the follow-up PGF `20261019-ols-parity`.
- `gridpane-core/references/ols.md`: the OpenLiteSpeed model — config tree,
  `gpols` commands, logs, LSCache, security and PHP (LSAPI) — with 10 KB sources
  recorded and the open items noted in `OPEN-QUESTIONS.md`.
- `gridpane-core`: treat OLS as a first-class stack — expanded `paths.md` (config
  tree, per-site vhost/rewrites, logs), `stack-overview.md` (LSAPI, LSCache,
  `lshttpd`) and `gp-conventions.md` (`gpols` read/write split and scope).
- `gridpane-nginx-config`: add the OLS configuration workflow and snippets —
  per-site `ols/headers.conf`, `ols/rewrites.conf`, and IP allow/deny files,
  with `gpols test`/`gpols site`/`gpols httpd` and rollbacks — and list the
  Nginx features with no OLS equivalent.
- `gridpane-wordpress/references/caching.md`: add the OLS/LSCache branch —
  `X-LiteSpeed-Cache`/`X-LiteSpeed-Cache-Control` verification, the
  `ols-page-cache`/`ols-redis-cache`/`cache-type` env keys, `wp litespeed-purge`
  purging, and OLS-specific failure causes.
- `gridpane-security`: add the OLS security branches — 7G on OLS (error page,
  `7g.log`, `ols/7g-*.conf` allow/deny, `gpols site`), ModSec paths on OLS,
  OLS logs for Fail2ban investigations, and the OLS Cloudflare real-IP path
  (`cf_ols.ip` → `allow ALL, <ranges>T`).
- `gridpane-server-diagnostics`: OLS-aware diagnostics — `lshttpd` checks, OLS
  log one-liners, a note that OLS uses LSAPI (no PHP-FPM pools), and
  `gp-healthcheck.sh` now reads OLS per-site access logs for 5xx counts.
- `gridpane-tooling`: add the OLS tooling paths (`gpols`/`ols`,
  `/usr/local/lsws/conf`, OLS logs) to the server layout and architecture.
- OLS parity wire-up: add OLS prompts to the trigger evals, and update the README
  skill table and PLAN milestone to reflect full OpenLiteSpeed coverage.

## v0.2.0 - 2026-10-16

### Added

- `gridpane-tooling`: the developer view of GridPane servers.
  `references/server-layout.md` maps the deployed tooling (`/usr/local/bin/gp`,
  `gp<cmd>` wrappers, `lib/`, `monit-scripts/`, `gridpane.ver`), `/etc/monit`,
  GridPane state and credentials (`/opt/gridpane`, `/root/gridcreds`,
  `/root/gridenv`), config and log locations, schedules, and the paths an update
  overwrites. Sourced from a maintainer-supplied snapshot of the deployed scripts
  (`tmp/gpcli`).
- `gridpane-tooling/references/gp-architecture.md` and
  `references/gp-command-reference.md`: the `gp` dispatcher/wrapper/`lib` model,
  versioning and update flow, monit integration, and the complete top-level
  command tree (including internal commands such as `audit`, `conf` and
  `function-run`) mapped to the functions they call.
- `gridpane-tooling/references/developing-tools.md`: where custom tooling may
  live, config I/O via the env files, logging and redaction, callbacks and
  notifications, the monit → `gpmonitor` → Slack worked example, and the
  testing/deploy conventions.
- `gridpane-tooling/scripts/scrape-docs.sh` and
  `references/docs-manifest.json`: a read-only KB indexer (sitemap → manifest of
  url/title/lastmod/fetched_at/sha256, optional Markdown via pandoc) plus
  `references/docs.md` documenting the pipeline and the deferred Upvoty-backed
  changelog. Offline test in `tests/scripts/test_scrape_docs.sh`, wired into CI.
- `tests/triggers/gridpane-tooling.yaml` (8 should / 5 should-not) and a README
  skill-table row for `gridpane-tooling`; `gridpane-core` and `gridpane-gp-cli`
  cross-link the new references.

- `gridpane-core/references/gridenv.md`: the `/root/gridenv` server-state files
  (active-sites, promethean, nginx, php{VERSION}, mysql, redis*, monit, backups,
  sys-upgrades, ACME), with a key reference, secret-key list and safe read
  patterns. Sourced from a maintainer-supplied server capture (redacted) plus KB
  pages.
- `gridpane-core/references/site-env.md`: the per-site
  `/var/www/{site.url}/logs/{site.url}.env` state file — the recorded page-cache
  method (`cache-type`), Redis object cache, PHP/pool, WAF and cron keys, and the
  secret keys to redact. Sourced from a maintainer-supplied site `logs/` capture
  (secrets redacted) plus the WP-Cron KB page.
- `gridpane-server-diagnostics/scripts/gp-healthcheck.sh` now reports the GridPane
  environment (server version/build, active-site count, Redis page/object cache
  configured), checks `redis-page`/`redis-object` service states, and with
  `--site` reports the site's recorded page-cache method (`cache-type`) and
  object-cache state from its per-site env (falling back to its Nginx config).

### Changed

- `scripts/lint-skills.sh` excludes the generated `docs-manifest.json` from the
  prose domain/secret/IP scans (it is machine-generated metadata whose page
  titles mention third-party domains).
- `gridpane-wordpress/references/caching.md`: document both page-cache header
  families — `X-Grid-SRCache-Fetch`/`X-Grid-SRCache-TTL`/`x-grid-srcache-skip`
  for Redis page caching and `X-Grid-Cache`/`X-Grid-Cache-TTL`/`x-grid-cache-skip`
  for FastCGI — and warn that a missing `X-Grid-Cache` does not mean a site is
  uncached. Add server-side cross-checks: the per-site Nginx cache config
  filenames and directives, the per-site `logs/{site.url}.env` state file, the
  per-site skip includes, and the server-wide `/root/gridenv/nginx.env` cache
  keys, so header and config can be confirmed against each other.
- `gridpane-core/references/gridenv.md`: correct the single-vs-split Redis rule.
  On a real capture `redis.env`, `redis-page.env` and `redis-object.env` all
  coexisted (and `redis-server:true` alongside `redis-page:true` /
  `redis-object:true`), so use the `promethean.env` flags and `monit.env` service
  prefixes, not `redis.env` presence. Add a worked cache example from the
  capture.
- `gridpane-core/references/paths.md`: add the `/root/gridenv` state files, the
  per-site Nginx cache config files, and the per-site `logs/{site.url}.env`.
- Phase 6 evaluation: trigger evals for `gridpane-core`, the five scenario
  walkthroughs in `tests/scenarios/` and `tests/safety-review.md`.
- Broader trigger evals and a `gridpane-core` trigger file.

## v0.1.0 - 2026-10-07

First release. Eight Agent Skills for operating GridPane-managed WordPress
servers, plus packaging and lint tooling.

### Added

- `gridpane-core`: orientation skill. Server stack layout, verified filesystem
  paths (`references/paths.md`), `gp` command conventions
  (`references/gp-conventions.md`), the full safety protocol and confirmation
  template (`references/safety.md`), a request-flow overview
  (`references/stack-overview.md`) and the source log
  (`references/sources.md`).
- `gridpane-server-diagnostics`: read-only server diagnosis with references for
  PHP-FPM (`max_children`, slow log), MySQL/MariaDB (processlist, table locks,
  slow log, connections), and logs (one-liners for top IPs, 5xx and bots), plus
  `scripts/gp-healthcheck.sh` (read-only; `--json`, `--site`).
- `gridpane-incident-triage`: symptom-based decision tree (down/timeout, 502/503/
  504, 500/white screen, slow, high load, disk full, SSL, redirect loop, DB
  connection) with handoffs, and `references/rca-template.md`.
- `gridpane-gp-cli`: `references/command-reference.md` with the verified `gp`
  command set, each labelled [READ]/[WRITE]/[DESTRUCTIVE], plus scope gotchas.
- `gridpane-nginx-config`: supported Nginx include locations and a
  backup-validate-reload workflow, with `references/snippets.md` (block xmlrpc,
  rate-limit wp-login, headers, redirects, allow/deny, cache exclusions) and OLS
  notes.
- `gridpane-wordpress`: WP-CLI as the correct system user, `references/caching.md`
  (FastCGI vs Redis page cache vs object cache, `X-Grid-Cache` headers, purge,
  "cache isn't working" causes), GP-Cron, staging, migrations and WP_DEBUG.
- `gridpane-security`: `references/waf.md` (6G/7G/ModSecurity enable, logs,
  whitelisting), `references/fail2ban.md`, `references/cloudflare.md` and
  `references/compromise-first-response.md`.
- `gridpane-api`: `references/endpoints.md`, `scripts/gp-api.sh` (token from
  `GRIDPANE_API_TOKEN`, `--yes` for mutating calls, 429 back-off) and
  `scripts/gp-inventory.sh`.
- Packaging: `scripts/install.sh` (copy/symlink, always installs
  `gridpane-core`, idempotent) and `scripts/lint-skills.sh` (frontmatter, command
  labels, relative links, secrets, IPs, domains), plus a GitHub Actions workflow.
- Tests: `tests/triggers/*.yaml` for every skill and a fixture-based
  `tests/scripts/test_gp_api.sh` that never calls the live API.

### Changed

- Phase 0 scaffold, `LICENSE` (MIT, pending maintainer confirmation),
  `.editorconfig`, `.gitignore`, `OPEN-QUESTIONS.md` and a `skills/_template`.

### Known gaps

- Some GridPane specifics remain unverified and are listed in
  `OPEN-QUESTIONS.md` (notably the API servers/sites endpoints and a few
  config filenames). They are marked as unverified in the relevant references.
