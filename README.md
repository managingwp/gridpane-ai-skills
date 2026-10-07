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
| `gridpane-server-diagnostics` | Checking load, PHP-FPM pools, MySQL/MariaDB, Redis, disk, logs and services | Read |
| `gridpane-gp-cli` | Running or explaining `gp` commands for sites, stack, PHP, caching and backups | Read / Write |
| `gridpane-nginx-config` | Adding or reviewing custom Nginx (or OpenLiteSpeed) includes and overrides | Write |
| `gridpane-wordpress` | WP-CLI as the site user, caching (FastCGI / Redis Page / Object), cron, staging and migrations | Read / Write |
| `gridpane-security` | 7G/6G WAF, ModSecurity, Fail2ban, Cloudflare real-IP/proxy setup, and compromised-site first response | Read / Write |
| `gridpane-api` | Fleet-wide inventory and actions through the GridPane REST API | Read / Write |

**Mode** describes what the skill may do by default. *Read* skills only inspect. *Write* skills propose changes and run them only after explicit confirmation (see [Safety model](#safety-model)).

---

## Install

Skills are plain folders. Copy or symlink the ones you want into your agent's skills directory:

```bash
git clone https://github.com/<org>/gridpane-ai-skills.git
cd gridpane-ai-skills

# Claude Code (user-wide)
mkdir -p ~/.claude/skills && cp -r skills/* ~/.claude/skills/

# Claude Code (per-project)
mkdir -p .claude/skills && cp -r /path/to/gridpane-ai-skills/skills/* .claude/skills/

# Agents that read .agents/skills (Codex, OpenCode, Copilot, etc.)
mkdir -p .agents/skills && cp -r /path/to/gridpane-ai-skills/skills/* .agents/skills/
```

Or use the installer, which copies (or, with `--link`, symlinks) the skills and
always includes `gridpane-core`:

```bash
scripts/install.sh --target ~/.claude/skills
scripts/install.sh --target .agents/skills --link
scripts/install.sh --target .claude/skills --skills gridpane-incident-triage
```

Always install `gridpane-core`. The other skills reference it.

---

## Requirements

- SSH access to GridPane servers as **root** (or a sudo user), for server-side skills
- A GridPane **API token** in `GRIDPANE_API_TOKEN`, for `gridpane-api` only. Never commit it.
- `bash`, `curl` and `jq` on the machine running API scripts

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
│   ├── _template/          # skeleton for new skills
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
│   └── gridpane-api/
│       ├── references/     # endpoints.md
│       └── scripts/        # gp-api.sh, gp-inventory.sh
├── scripts/                # install.sh, lint-skills.sh
└── tests/                  # trigger evals, script tests, scenarios
```

---

## Disclaimer

This is an independent community project. It is **not** affiliated with or endorsed by GridPane. GridPane changes over time: the skills cite their sources and record a "last verified" date, so check the official [GridPane Knowledge Base](https://gridpane.com/kb/) when something doesn't match. You are responsible for the commands an agent runs on your servers.

## License

MIT (proposed; confirm before first release).
