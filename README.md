# gridpane-ai-skills

Agent Skills for operating **GridPane**-managed WordPress servers: diagnosing, tuning and securing them safely.

These skills teach an AI agent (Claude Code, Codex, GitHub Copilot, OpenCode or any tool that supports the open `SKILL.md` format) how a GridPane server is laid out, which commands are safe to run, and how to work through common incidents. The agent gets the same mental model an experienced GridPane operator already has.

> Status: **in development.** See [PLAN.md](PLAN.md) for the build plan and [AGENTS.md](AGENTS.md) for contributor and agent rules.

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

### Manual install (offline)

Skills are plain folders, so you can clone and copy them yourself. Use `skills/gridpane-*` rather than `skills/*` so the internal scaffold (`skills/_template`) is not copied:

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
| `scripts/lint-skills.sh` | Repository checks: frontmatter, command labels, relative links, secrets, IPs, domains. Run before committing; exits non-zero on a problem |
| `scripts/gridpane-kb-docs.sh` | Scrape, inspect and manage the KB cache. `status` reports ingested / cached / extracted / drift without a request; `check` is one request (exit 3 when the KB moved); `refresh` indexes a dated snapshot and publishes only where the KB changed; `list`, `search`, `diff`, `extract` and `prune` browse, query, compare, convert and trim |

Shipped with the skills and used by them:

| Script | Skill | What it does |
|---|---|---|
| `gp-healthcheck.sh` | `gridpane-server-diagnostics` | Read-only sweep of load, memory, disk, services and PHP-FPM pools (`--json`, `--site`) |
| `gp-api.sh` | `gridpane-api` | Thin request wrapper for the GridPane API; token from `GRIDPANE_API_TOKEN` |
| `gp-inventory.sh` | `gridpane-api` | Server and site inventory export |
| `scrape-docs.sh` | `gridpane-tooling` | Index, search and extract the GridPane Knowledge Base (WordPress REST feed, sitemap fallback). Maintainer tooling — see `skills/gridpane-tooling/references/docs.md` |
| `scrape-changelog.sh` | `gridpane-tooling` | Changelog digest from Upvoty's public JSON API |

Every script takes `--help`. `tests/scripts/*.sh` are the offline test suites; they are not part of an install and touch no network (the KB and snapshot cases run against a loopback fixture server).

---

## Requirements

- SSH access to GridPane servers as **root** (or a sudo user), for server-side skills
- A GridPane **API token** in `GRIDPANE_API_TOKEN`, for `gridpane-api` only. Never commit it.
- `bash`, `curl` and `jq` on the machine running API and KB scripts
- `python3` only for the repository test suites

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
├── PLAN.md                 # build plan and acceptance criteria
├── OPEN-QUESTIONS.md       # unverified facts and scope proposals
├── LICENSE
├── CHANGELOG.md
├── skills/
│   ├── _template/          # internal skeleton, hidden from npx skills
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
│   └── gridpane-api/
│       ├── references/     # endpoints.md
│       └── scripts/        # gp-api.sh, gp-inventory.sh
├── scripts/                # install.sh, lint-skills.sh, gridpane-kb-docs.sh
└── tests/                  # trigger evals, script tests (test_scrape_docs.sh, ...), scenarios
```

---

## Disclaimer

This is an independent community project. It is **not** affiliated with or endorsed by GridPane. GridPane changes over time: the skills cite their sources and record a "last verified" date, so check the official [GridPane Knowledge Base](https://gridpane.com/kb/) when something doesn't match. You are responsible for the commands an agent runs on your servers.

## License

MIT. See [LICENSE](LICENSE).
