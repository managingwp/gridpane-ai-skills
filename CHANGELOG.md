# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
