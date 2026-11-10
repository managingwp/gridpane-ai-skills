# gridpane-ai-skills

Agent Skills for operating **GridPane**-managed WordPress servers: diagnosing, tuning and securing them safely.

These skills teach an AI agent (Claude Code, Codex, GitHub Copilot, OpenCode or any tool that supports the open `SKILL.md` format) how a GridPane server is laid out, which commands are safe to run, and how to work through common incidents. The agent gets the same mental model an experienced GridPane operator already has.

> Status: **v0.6.0 released.** See [CHANGELOG.md](CHANGELOG.md) for release history and [AGENTS.md](AGENTS.md) for contributor and agent rules.

---

## What's covered

| Skill | Use it when… | Mode |
|---|---|---|
| `gridpane-core` | Any GridPane task. Covers stack layout, paths, the `gp` CLI conventions and the safety protocol. Other skills depend on it. | Read |
| `gridpane-incident-triage` | A site is down, slow, throwing 502/504/500, or a server alert fired | Read → Write |
| `gridpane-server-diagnostics` | Checking load, PHP workers (PHP-FPM on Nginx, LSAPI on OLS), MySQL/MariaDB, Redis, disk, logs and services | Read |
| `gridpane-gp-cli` | Running or explaining `gp` commands for sites, stack, PHP, caching and backups, including backup troubleshooting (spinner, no-op schedules) | Read / Write |
| `gridpane-nginx-config` | Adding or reviewing custom Nginx includes or OpenLiteSpeed `ols/` headers, rewrites and IP allow/deny | Write |
| `gridpane-wordpress` | WP-CLI as the site user, caching (FastCGI / Redis Page / Object / LSCache), cron, staging and migrations | Read / Write |
| `gridpane-security` | 7G/6G WAF (6G is Nginx-only), ModSecurity, Fail2ban, Cloudflare real-IP/proxy setup, and compromised-site first response | Read / Write |
| `gridpane-api` | Fleet-wide inventory and actions through the GridPane REST API | Read / Write |
| `gridpane-tooling` | Building, deploying or debugging custom tooling on a GridPane server: the `/usr/local/bin` + `lib/` scripts, the `gp` dispatcher, config/log locations, monit hooks and the docs manifest | Read |
| `gridpane-kb-refresh` | Refreshing the GridPane Knowledge Base and the skills that cite it: drift check, snapshot, the files a changed article affects, and the gate | Read → Write |
| `gridpane-citation-audit` | Auditing the skills' KB citations: dead or renamed links, new articles nothing cites, and facts that changed after a file was last verified | Read |

**Mode** describes what the skill may do by default. *Read* skills only inspect. *Write* skills propose changes and run them only after explicit confirmation (see [Safety model](#safety-model)).

Both GridPane web servers are covered: **Nginx** (PHP-FPM, FastCGI/Redis page cache) and **OpenLiteSpeed** (LSAPI, LSCache), with their different paths, commands and logs.

---

## Install

### With `npx skills` (recommended)

The [skills CLI](https://github.com/vercel-labs/skills) downloads the skills, links them into the agents you use, and tracks them for updates:

```bash
# Interactive: pick the skills and the agents (Claude Code, Codex, OpenCode, Cursor, ...)
npx skills add managingwp/gridpane-ai-skills

# Install every GridPane skill for one agent, globally
npx skills add managingwp/gridpane-ai-skills --skill '*' -a opencode -g

# Non-interactive, project scope
npx skills add managingwp/gridpane-ai-skills --skill '*' -a claude-code -y

# List what the repository offers without installing
npx skills add managingwp/gridpane-ai-skills --list
```

Use `--copy` instead of the default symlinks when your agent does not follow them.

A single-skill install must include `gridpane-core`, because the other skills rely on its paths, `gp` conventions and safety protocol:

```bash
npx skills add managingwp/gridpane-ai-skills --skill gridpane-core --skill gridpane-incident-triage -a claude-code
```

Update or remove installed skills later:

```bash
npx skills update
npx skills remove gridpane-security
npx skills list
```

### claude.ai (chat)

There are two routes. Both install the same eleven skills, and neither gives the chat sandbox SSH access to your server.

#### Plugin marketplace

The repository is a Claude plugin marketplace that lists one plugin, `gridpane`, containing every skill.

1. In claude.ai open **Customize → Plugins**.
2. Click **Add**, then **Add marketplace**.
3. Choose **Add from a repository** and paste `https://github.com/managingwp/gridpane-ai-skills`.
4. Choose **Sync**, then install **gridpane**.

Claude Code users can register the same marketplace from the terminal:

```text
/plugin marketplace add managingwp/gridpane-ai-skills
/plugin install gridpane --marketplace managingwp/gridpane-ai-skills
```

#### Per-skill ZIPs

Download the archive you need from the [Releases](https://github.com/managingwp/gridpane-ai-skills/releases) page: `gridpane-core.zip`, a `gridpane-<name>.zip`, or `gridpane-skills-all.zip`. Each standalone archive carries local copies of the core references and of the sibling references it cites, so it works without the other skills. The skill folder is the ZIP's top level, which is what claude.ai requires.

1. In claude.ai open **Customize → Skills**.
2. Click **+**, then **+ Create skill**.
3. Choose **Upload a skill** and select the ZIP.
4. Repeat with `gridpane-core.zip`. Uploading core as well is recommended: it carries the full safety model and path reference.

#### Chat limitations

claude.ai chat has no SSH connection to your server and no GridPane API token unless you attach a server connector. Claude therefore gives you commands to run and works from the output you paste back; it cannot inspect a live server on its own. Use Claude Code or another local agent when you want the agent to run commands directly.

### Manual install (offline)

Skills are plain folders, so you can clone and copy them yourself. Use `skills/gridpane-*` rather than `skills/*` so only the production skills are copied (the skeleton now lives in `templates/skill`):

```bash
git clone https://github.com/managingwp/gridpane-ai-skills.git
cd gridpane-ai-skills

# Claude Code (user-wide)
mkdir -p ~/.claude/skills && cp -r skills/gridpane-* ~/.claude/skills/

# Claude Code (per-project)
mkdir -p .claude/skills && cp -r skills/gridpane-* .claude/skills/

# Agents that read .agents/skills (Codex, OpenCode, Copilot, etc.)
mkdir -p .agents/skills && cp -r skills/gridpane-* .agents/skills/
```

The installer does the same, copying (or, with `--link`, symlinking) the skills and always including `gridpane-core`:

```bash
scripts/install.sh --target ~/.claude/skills
scripts/install.sh --target .agents/skills --link
scripts/install.sh --target .claude/skills --skills gridpane-incident-triage
```

Always install `gridpane-core`. The other skills reference it.

---

## Scripts

Repository tooling, run from a clone:

| Script | What it does |
|---|---|
| `scripts/install.sh` | Copy or symlink skills into an agent's skills directory (`--target`, `--link`, `--skills`); always includes `gridpane-core` |
| `scripts/build-zips.sh` | Build `dist/<skill>.zip` for each skill and `dist/gridpane-skills-all.zip`. Standalone archives bundle the core and sibling references they cite; output is deterministic and size-checked |
| `scripts/git-squash-release.sh` | Vendored release helper. A release assigns the version from the last tag to `VERSION`, both Claude manifests and `CHANGELOG.md`, then squashes commits and tags |
| `scripts/lint-skills.sh` | Repository checks: frontmatter, command labels, relative links, absolute package paths, secrets, IPs, domains, and Claude version sync. Run before committing; exits non-zero on a problem |
| `scripts/gridpane-kb-docs.sh` | Scrape, inspect and manage the KB cache. `status` reports ingested / cached / extracted / drift without a request; `check` is one request (exit 3 when the KB moved); `refresh` indexes a dated snapshot and publishes only where the KB changed; `affected` lists the `file:line` in `skills/` that cites each changed article, which is how a KB refresh drives a skill update; `audit` checks the citations themselves (unknown, uncited-new, stale, coverage, and `--probe` for moved/down); `list`, `search`, `diff`, `extract` and `prune` browse, query, compare, convert and trim |
| `scripts/gridpane-kb-weekly.sh` | The unattended half of that loop: index the KB into an isolated cache, compare it with the baseline the last delivered report acknowledged, and email the articles that need review. Report-only; writes nothing tracked |
| `scripts/gridpane-kb-history.sh` | Render the weekly job's ledger as `KB-CHANGES.md`: every monitored KB change, newest first, grouped by year and month, with the `file:line` that cites each article. `--backfill` seeds from retained snapshots, `--check` fails when the committed history is stale |
| `scripts/install-kb-weekly-timer.sh` | Install or remove the weekly check as a systemd user timer (`--calendar`, `--unit-dir`, `--dry-run`, `--uninstall`) |

Shipped with the skills and used by them:

| Script | Skill | What it does |
|---|---|---|
| `gp-healthcheck.sh` | `gridpane-server-diagnostics` | Read-only sweep of load, memory, disk, services and PHP-FPM pools (`--json`, `--site`) |
| `gp-api.sh` | `gridpane-api` | Thin request wrapper for the GridPane API; token from `GRIDPANE_API_TOKEN` |
| `gp-inventory.sh` | `gridpane-api` | Server and site inventory export |
| `scrape-docs.sh` | `gridpane-tooling` | Index, search and extract the GridPane Knowledge Base (WordPress REST feed, sitemap fallback). Maintainer tooling — see `skills/gridpane-tooling/references/docs.md` |
| `scrape-changelog.sh` | `gridpane-tooling` | Changelog digest from Upvoty's public JSON API |

Every script takes `--help`. `tests/scripts/*.sh` are the offline test suites; they are not part of an install and touch no network (the KB and snapshot cases run against a loopback fixture server).

### Weekly KB report

`scripts/gridpane-kb-weekly.sh` is the unattended half of the refresh loop. It indexes the KB into its own cache under the gitignored `out/gridpane-kb-weekly/`, compares the result with the baseline the last delivered report acknowledged, and emails the articles a person should read: the `file:line` that cites each one, the articles nothing cites, and the caveat that a body-hash change may be markup only. It edits nothing, commits nothing and never touches `skills/gridpane-tooling/references/docs-manifest.json`, so a scheduled run and a manual refresh cannot race. No article changed means no email; a scrape or delivery failure always sends one.

Mail goes through the configured `send-email` transport, which owns the recipient. The script has no address option, so a scheduled run cannot mail anywhere else:

```bash
# [READ] Decide without network, lock, writes or mail.
scripts/gridpane-kb-weekly.sh --dry-run --json

# [WRITE] One live run; writes only under out/gridpane-kb-weekly/.
scripts/gridpane-kb-weekly.sh

# [READ] Show the rendered units without installing anything.
scripts/install-kb-weekly-timer.sh --dry-run
```

```bash
# [WRITE] Install the user units, then enable the timer yourself.
scripts/install-kb-weekly-timer.sh
systemctl --user enable --now gridpane-kb-weekly.timer
```

The timer runs Mondays at 08:00 UTC by default (`--calendar` changes it) with `Persistent=true`, so a run missed while the machine was off happens at the next start. Results go to the journal; `state/last-run.json` and `state/last-report.txt` hold the last outcome and the last report. A failed send leaves the baseline in place, so the next run recomputes those changes instead of losing them. Stop it with `systemctl --user disable --now gridpane-kb-weekly.timer`; `scripts/install-kb-weekly-timer.sh --uninstall` removes the units. Settings can be overridden per machine in `~/.config/gridpane-kb-weekly/env`, which the service reads when it exists.

### KB change history

Each weekly run appends one record to the gitignored
`out/gridpane-kb-weekly/state/history.jsonl`, so the schedule still writes nothing
tracked. `scripts/gridpane-kb-history.sh` renders that ledger into
[`KB-CHANGES.md`](KB-CHANGES.md): every added, removed, body-changed and
title-only article, newest first and grouped by year and month, with the
`file:line` that cites each one.

```bash
# [WRITE] Regenerate KB-CHANGES.md and backfill any interval the ledger lacks.
scripts/gridpane-kb-history.sh --backfill

# [READ] Exit 3 when the committed history no longer matches the ledger.
scripts/gridpane-kb-history.sh --check
```

History starts at the earliest retained snapshot (2026-10-21); earlier KB changes
are described in `CHANGELOG.md`. A body-"change" means the rendered hash moved,
so read the article before editing a citation.

---

## Requirements

- SSH access to GridPane servers as **root** (or a sudo user), for server-side skills
- A GridPane **API token** in `GRIDPANE_API_TOKEN`, for `gridpane-api` only. Never commit it.
- `bash`, `curl` and `jq` on the machine running API and KB scripts
- `python3` for the repository test suites, `scripts/build-zips.sh`, and the Claude version updates in the release helper

---

## Safety model

GridPane servers are usually live production hosting for paying clients. Every skill follows the same protocol, defined in `skills/gridpane-core/references/safety.md`:

1. **Diagnose first.** Read-only commands (status, logs, config reads, `gp` info commands) can run freely.
2. **Propose, then confirm.** Before any change, the agent states the exact command(s), the expected effect, the blast radius (one site, or every site on the server) and the rollback. It waits for an explicit "yes".
3. **Back up before editing.** Any config file is copied to `<file>.bak-<timestamp>` before it is modified.
4. **Validate before reload.** `nginx -t` (or the OLS equivalent) runs before any reload. A failed test means no reload.
5. **Never by default:** deleting sites, dropping databases, `rm -rf`, editing GridPane-managed files that `gp` regenerates, rebooting, or bulk actions across the fleet. These need the user to name the action explicitly.
6. **Prefer `gp` over hand edits.** When GridPane provides a command for something, use it. Hand-edited managed files get overwritten.

---

## Example prompts

- "example.com is throwing 502s, figure out why" → `gridpane-incident-triage`
- "Which PHP-FPM pools on this box are hitting max_children?" → `gridpane-server-diagnostics`
- "Add a custom Nginx rule to block xmlrpc.php on example.com" → `gridpane-nginx-config`
- "List every site in our GridPane account with its PHP version and server" → `gridpane-api`
- "Set up Cloudflare real-IP correctly on this server" → `gridpane-security`
- "Clear all caches for example.com and check Redis is actually being used" → `gridpane-wordpress`

---

## Repository layout

```
gridpane-ai-skills/
├── README.md
├── AGENTS.md               # rules for agents/contributors working on this repo
├── OPEN-QUESTIONS.md       # unverified facts and scope proposals
├── LICENSE
├── CHANGELOG.md
├── VERSION                 # current release version, written by the release helper
├── .claude-plugin/
│   ├── marketplace.json    # claude.ai / Claude Code marketplace entry
│   └── plugin.json         # exposes every skills/gridpane-* skill
├── templates/
│   ├── skill/              # copyable skeleton, outside the discovery root
│   └── systemd/            # weekly KB report units, rendered at install time
├── skills/
│   ├── gridpane-core/
│   │   ├── SKILL.md
│   │   └── references/     # paths.md, gp-conventions.md, safety.md, sources.md, stack-overview.md
│   ├── gridpane-incident-triage/
│   │   └── references/     # rca-template.md
│   ├── gridpane-server-diagnostics/
│   │   ├── references/     # php-fpm.md, mysql.md, logs.md
│   │   └── scripts/        # gp-healthcheck.sh (read-only)
│   ├── gridpane-gp-cli/
│   │   └── references/     # command-reference.md
│   ├── gridpane-nginx-config/
│   │   └── references/     # snippets.md
│   ├── gridpane-wordpress/
│   │   └── references/     # caching.md
│   ├── gridpane-security/
│   │   └── references/     # waf.md, fail2ban.md, cloudflare.md, compromise-first-response.md
│   ├── gridpane-tooling/
│   │   ├── references/     # docs.md, docs-manifest.json, gp-command-reference.md, ...
│   │   └── scripts/        # scrape-docs.sh, scrape-changelog.sh
│   ├── gridpane-kb-refresh/
│   │   └── references/     # pipeline.md
│   ├── gridpane-citation-audit/
│   │   └── references/     # checks.md
│   └── gridpane-api/
│       ├── references/     # endpoints.md
│       └── scripts/        # gp-api.sh, gp-inventory.sh
├── dist/                   # generated skill ZIPs (gitignored)
├── scripts/                # install.sh, lint-skills.sh, build-zips.sh, git-squash-release.sh, ...
└── tests/                  # trigger evals, script tests (test_scrape_docs.sh, ...), scenarios
```

---

## Disclaimer

This is an independent community project. It is **not** affiliated with or endorsed by GridPane. GridPane changes over time: the skills cite their sources and record a "last verified" date, so check the official [GridPane Knowledge Base](https://gridpane.com/kb/) when something doesn't match. You are responsible for the commands an agent runs on your servers.

## License

MIT. See [LICENSE](LICENSE).
