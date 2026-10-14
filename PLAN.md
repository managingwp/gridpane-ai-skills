# PLAN.md: gridpane-ai-skills build plan

This plan is for the agent building this repo. Read [AGENTS.md](AGENTS.md) first: its rules (sources, safety labels, definition of done) apply to every item below.

Work through the phases in order and tick boxes as you go. Phases 2–4 can interleave once Phase 1 is complete, but `gridpane-core` must exist before any other skill is written.

**Important:** the topic lists below say *what to document*, not *what is true*. Verify every path, command and endpoint against the GridPane KB or API docs (or maintainer-supplied server output) before it goes into a skill. Anything you can't verify goes into `OPEN-QUESTIONS.md`.

---

## Phase 0: Scaffold

- [x] Create the directory layout shown in README.md (`skills/`, `scripts/`, `tests/triggers/`, `tests/scripts/`)
- [x] Add `LICENSE` (MIT; flag in OPEN-QUESTIONS.md for maintainer confirmation), `CHANGELOG.md` and `.gitignore` (ignore `.env`, `*.bak-*`, `out/`)
- [x] Add `.editorconfig` (LF, 2-space for md/yaml, 4-space or tab for sh, consistently)
- [x] Create `OPEN-QUESTIONS.md` with sections: *Unverified facts*, *Scope proposals*, *Needs real-server output*
- [x] Add a `skills/_template/SKILL.md` matching the structure in AGENTS.md
- [x] Commit: `chore: scaffold repository`

## Phase 1: Research and `gridpane-core`

Do the research once and capture it here so the other skills can link to it instead of repeating it.

- [x] **Research pass.** Read the GridPane KB sections on the CLI, the server stack (Nginx and OpenLiteSpeed), PHP, MySQL/MariaDB, caching, security (7G/6G, ModSecurity, Fail2ban), backups, staging, and the REST API. Record each page in `references/sources.md` with its URL, title and date checked.
- [x] `skills/gridpane-core/SKILL.md`: the orientation skill. Purpose: give the agent the GridPane mental model before it touches anything. The description must make it load for *any* GridPane mention.
- [x] `references/paths.md`: verified locations of:
  - site webroot, site-level logs, and Nginx/OLS access and error logs
  - per-site and server-level custom config include locations (the safe places to customise)
  - PHP-FPM pool configs and logs per PHP version
  - MySQL/MariaDB config and logs; Redis config
  - GridPane's own logs and scripts that are useful for diagnosis
  - **files GridPane regenerates**: these must never be hand-edited
- [x] `references/gp-conventions.md`: how `gp` commands are structured (`gp site …`, `gp stack …`, etc.), how to discover help, and which commands are informational versus mutating
- [x] `references/safety.md`: the full safety protocol from README.md and AGENTS.md, written as instructions to the agent, including the exact confirmation template:
  ```
  PROPOSED CHANGE [WRITE]
  Command:      …
  Effect:       …
  Blast radius: site example.com only | all sites on server | fleet
  Backup:       …
  Rollback:     …
  Proceed? (yes/no)
  ```
- [x] `references/stack-overview.md`: request flow (Cloudflare/edge → Nginx or OLS → cache layers → PHP-FPM → MySQL/Redis), system users per site, and how a GridPane server differs from a vanilla Ubuntu LEMP box
- [x] `references/sources.md` populated
- [x] Commit: `feat(core): add gridpane-core skill`

## Phase 2: Diagnostic skills (read-only first)

### 2a. `gridpane-server-diagnostics`
- [x] SKILL.md workflow: load → memory/swap → disk/inodes → services → PHP-FPM pools → DB → Redis → web server errors → recent GridPane activity
- [x] `references/php-fpm.md`: reading pool status and logs, spotting `max_children` saturation and slow-log entries, and the per-site pool model
- [x] `references/mysql.md`: processlist, slow log, connection counts, InnoDB buffer sizing checks, finding the heavy site/DB
- [x] `references/logs.md`: which log answers which question, with `grep`/`awk` one-liners (top IPs, top URIs, 5xx by site, bot user agents)
- [x] `scripts/gp-healthcheck.sh`: **read-only** server snapshot (load, mem, disk, service states, per-pool PHP-FPM counts, top MySQL queries, recent 5xx counts per site). `--json` and `--site <domain>` flags.
- [x] Trigger evals + shellcheck

### 2b. `gridpane-incident-triage`
The umbrella workflow. It routes to the other skills and doesn't duplicate them.
- [x] Decision tree by symptom: **site down/timeout**, **502/504**, **500 / white screen**, **slow site**, **high load alert**, **disk full**, **SSL error**, **redirect loop** (often Cloudflare SSL mode plus origin redirects), **DB connection error**
- [x] For each: first three [READ] checks, likely causes ranked, the skill to hand off to, and a standard fix with confirmation
- [x] `references/rca-template.md`: a short root-cause write-up template (timeline, impact, root cause, fix, prevention) for client communication
- [x] Trigger evals

## Phase 3: Operational skills (read + write)

### 3a. `gridpane-gp-cli`
- [x] `references/command-reference.md`: verified `gp` commands grouped by area (site info, PHP version and settings, caching, SSL, WP-CLI wrappers, stack/services, backups), each labelled [READ]/[WRITE]/[DESTRUCTIVE]
- [x] SKILL.md: how to find the right command, check its help output before running, and prefer `gp` over hand edits
- [x] Gotchas: commands that restart services or affect every site on the server

### 3b. `gridpane-nginx-config`
- [x] Supported customisation points for Nginx **and** OpenLiteSpeed (note where they differ; if OLS is out of scope for v1, say so)
- [x] Workflow: identify the stack → locate the correct include → back up → write → `nginx -t` → reload → verify with `curl -I`
- [x] `references/snippets.md`: vetted examples: block `xmlrpc.php`, rate-limit `wp-login.php`, custom headers, redirects, upload size, bypassing cache for a path, allowing/denying by IP
- [x] Rollback for every snippet

### 3c. `gridpane-wordpress`
- [x] WP-CLI as the correct site system user (never as root against site files); the `gp` WP-CLI wrapper if one exists
- [x] `references/caching.md`: FastCGI vs Redis page cache vs Redis object cache; how to check which is active, verify hits (response headers), purge per site, and common "cache isn't working" causes (cookies, query strings, logged-in users, WooCommerce pages)
- [x] Cron: WP-Cron vs system cron on GridPane; duplicate-cron problems on multi-server or load-balanced setups
- [x] Staging: push/pull behaviour, what gets overwritten, why push-to-live is [DESTRUCTIVE]
- [x] Migrations: checklist (DNS, SSL, search-replace, cache, cron, email), not a script
- [x] Debugging: enabling `WP_DEBUG` safely and turning it back off, reading `debug.log`, plugin bisecting with `--skip-plugins`
- [x] Hand-off note: suspected compromise → `gridpane-security`

## Phase 4: Security and API

### 4a. `gridpane-security`
- [x] `references/waf.md`: 7G/6G and ModSecurity: enabling per site, reading what was blocked, whitelisting a false positive the supported way
- [x] `references/fail2ban.md`: status and jails, finding and unbanning an IP ([WRITE]), checking whether you are banning Cloudflare IPs
- [x] `references/cloudflare.md`: real visitor IP restoration at the origin, SSL mode (Full (strict)), origin certificates vs Let's Encrypt, caching interplay, and locking the origin to Cloudflare IPs (with the risks)
- [x] `references/compromise-first-response.md`: contain → preserve evidence (copy logs before rotation) → identify → clean → harden. Use read-only detection only, and point to deeper hacked-site triage tooling where available. Never write or run payloads.
- [x] Trigger evals, including should-not prompts for generic non-GridPane security questions

### 4b. `gridpane-api`
- [x] `references/endpoints.md`: verified endpoints, auth header format, pagination, rate limits and error shapes. Every mutating endpoint labelled [WRITE]/[DESTRUCTIVE].
- [x] `scripts/gp-api.sh`: thin wrapper (`gp-api.sh GET /server`), token from env, never echoed, `--yes` required for non-GET, respects rate limits with back-off
- [x] `scripts/gp-inventory.sh`: exports servers and sites (domain, server, PHP version, stack, SSL status where available) as JSON and CSV
- [x] SKILL.md: fleet questions ("which sites run PHP 8.1?") answered from inventory; **no fleet-wide mutating actions** without per-target confirmation
- [x] `tests/scripts/` with mocked API responses (fixtures), so tests never call the live API

## Phase 5: Packaging

- [x] `scripts/install.sh --target <dir> [--link] [--skills a,b,c]`: copies or symlinks skills, always includes `gridpane-core`, idempotent
- [x] `scripts/lint-skills.sh` (spec in AGENTS.md)
- [x] GitHub Actions: run shellcheck, lint-skills and script tests on push and PR
- [x] Update README.md skill table and install section to match reality
- [x] Tag `v0.1.0` and write CHANGELOG

## Phase 6: Evaluation

- [x] `tests/triggers/<skill>.yaml` for every skill:
  ```yaml
  should_trigger:
    - "example.com on gridpane is giving 502 bad gateway"
  should_not_trigger:
    - "how do I set up nginx on a fresh ubuntu box"
  ```
- [x] Check sibling skills don't collide (e.g. "clear cache" should hit `gridpane-wordpress`, not `gridpane-gp-cli`; resolve overlaps by sharpening descriptions)
- [x] Scenario walkthroughs: for 5 incidents (502 from PHP-FPM saturation, disk full from logs, redirect loop from Cloudflare Flexible SSL, cache not hitting on WooCommerce, Fail2ban banning Cloudflare), write the expected agent path in `tests/scenarios/*.md` and confirm the skills lead there
- [x] Safety review: grep every [WRITE]/[DESTRUCTIVE] command and confirm each has a backup step, a confirmation and a rollback
- [x] Final pass over `OPEN-QUESTIONS.md`; hand it to the maintainer

---

## Out of scope for v0.1

- RunCloud, SpinupWP or other panels (the format could extend to them later as separate repos or skills)
- Automated remediation daemons or anything that runs unattended
- Provisioning new servers through the API
- Client-specific runbooks (keep those in a private repo that depends on this one)

## Milestones

| Version | Contents |
|---|---|
| v0.1.0 | Phases 0–2 + `gridpane-gp-cli`, lint and install tooling |
| v0.2.0 | Remaining Phase 3 + Phase 4 |
| v0.3.0 | Phase 6 evals complete, open questions resolved |
