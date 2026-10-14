# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

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
