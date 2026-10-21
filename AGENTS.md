# AGENTS.md

Instructions for AI agents (and humans) building and maintaining this repository. Read this file and [PLAN.md](PLAN.md) before making changes.

## Mission

Build a set of high-quality, **accurate** and **safe** Agent Skills for GridPane-managed servers. Accuracy matters more than coverage: one wrong command run on a production server costs more than ten missing features.

## Ground rules

1. **Follow PLAN.md in order.** Work phase by phase. Tick checkboxes in PLAN.md as you complete items, and commit after each completed item or small group of items.
2. **Never invent GridPane specifics.** Paths, `gp` command syntax, API endpoints, config filenames and service names must come from a source:
   - the official GridPane Knowledge Base (`gridpane.com/kb/`) or API docs, or
   - output captured from a real GridPane server and supplied by the maintainer.
   Record every source in `skills/gridpane-core/references/sources.md` with the URL and the date you checked it.
3. **Mark uncertainty explicitly.** When you can't verify a detail, keep it out of the instructions. Add it to the `## Unverified` section at the bottom of that skill's reference file and list it in `OPEN-QUESTIONS.md` for the maintainer. Never present a guess as fact.
4. **Don't access real servers or real credentials.** You are writing documentation and scripts, not operating infrastructure. Don't put real hostnames, IPs, domains, tokens or client names in the repo. Use `example.com`, `staging.example.com`, `203.0.113.10` (RFC 5737) and `GRIDPANE_API_TOKEN`.
5. **Ask before scope changes.** Adding or removing a skill, or changing the safety model, needs maintainer sign-off. Note the proposal in `OPEN-QUESTIONS.md` and continue with other work.

## Skill format

Every skill is a folder in `skills/<skill-name>/` that follows the open Agent Skills format.

```
skills/<skill-name>/
├── SKILL.md            # required
├── references/         # optional: longer docs loaded on demand
└── scripts/            # optional: executable helpers
```

### SKILL.md requirements

```markdown
---
name: gridpane-example            # must equal the folder name; lowercase, hyphens
description: >-                   # ≤ 1024 chars; says WHAT it does and WHEN to use it,
  ...                             # including the trigger phrases a user would type
---
```

- **Description** is the trigger. Lead with the situation ("Use when a GridPane site returns 502/504…"), include real user phrasing, and name the GridPane terms (gp, GridPane, FastCGI cache, 7G…). Say when **not** to use it if a sibling skill is a better fit.
- **Body ≤ ~400 lines.** Put long command tables and config references in `references/*.md` and link them from the body ("Read `references/php-fpm.md` when…").
- **Structure of the body:**
  1. One-paragraph purpose
  2. `Prerequisites`: access needed, and a reminder to load `gridpane-core` first
  3. `Workflow`: numbered steps; diagnosis before action
  4. Commands, each labelled **[READ]**, **[WRITE]** or **[DESTRUCTIVE]**
  5. `Verify`: how to confirm the fix worked
  6. `Rollback`: for every [WRITE] step
  7. `Gotchas`: GridPane-specific traps (e.g. files that `gp` regenerates)
  8. `Last verified: YYYY-MM-DD` plus source links
- Write in the imperative, aimed at the agent ("Check…", "Run…", "Ask the user…").
- Explain *why* a step matters when it isn't obvious. Agents generalise better from reasons than from bare rules.

### Distribution

`skills/` is the published discovery root: `npx skills add managingwp/gridpane-ai-skills` offers every folder there that contains a `SKILL.md`.

- A new skill is not done until `npx skills add . --list` shows it (`Found N skills`, one more than before).
- Folders beginning with `_` are scaffolding, not skills: they must keep `metadata.internal: true` so the CLI hides them, and the marker must be removed when the folder is renamed to a real skill. `scripts/lint-skills.sh` enforces both directions.
- Never rely on a sibling skill being installed. `gridpane-core` is required, but the README and every description must still make sense when it is the only skill present.
- The CI discovery check pins the `skills` CLI version. Bump it in `.github/workflows/ci.yml` and re-run the README commands when you do.

### Command labels and the safety protocol

Every shell, `gp`, WP-CLI or API call in a skill must carry one label:

| Label | Meaning | Agent behaviour |
|---|---|---|
| **[READ]** | No state change | Run freely |
| **[WRITE]** | Changes config, cache, service state or data, and is reversible | Show the command, effect, blast radius and rollback; wait for confirmation; back up first |
| **[DESTRUCTIVE]** | Hard or impossible to reverse (delete site or DB, overwrite production from staging, mass operations) | Run only when the user named this exact action; confirm twice; verify a backup exists |

Clearing cache counts as [WRITE] because it's reversible but has an effect. Reloading or restarting a service is [WRITE]. Never chain [READ] and [WRITE] commands in a single pasted block.

## Scripts

- Use **Bash** (with `set -euo pipefail`) for server-side helpers and **Bash + curl + jq** for API helpers. Don't add other runtimes without sign-off.
- Server-side scripts in `gridpane-server-diagnostics/scripts/` must be **read-only**. They collect and print, and never modify.
- Every script needs `--help`, exits non-zero on failure, sends machine-readable output (`--json` where it makes sense) to stdout and diagnostics to stderr, and has no hard-coded hosts or secrets.
- API scripts read the token from `GRIDPANE_API_TOKEN` only, never print it, and default to GET. Mutating API calls need a `--yes` flag.
- Run `shellcheck` on every script. It must pass with no warnings, or carry a justified `# shellcheck disable=` comment.

## Repository tooling

- `scripts/lint-skills.sh` validates frontmatter (name matches folder, description length), checks that every command block carries a label, checks for broken relative links, and greps for secrets and real-looking IPs or domains.
- `tests/triggers/<skill>.yaml` holds sample prompts that **should** and **should not** trigger each skill (see PLAN.md, Phase 6).
- Run `scripts/lint-skills.sh` and `shellcheck` before each commit.

### Refreshing KB facts

Before shipping a change that cites GridPane knowledge-base facts, check whether the KB moved, and re-read only what it reports:

```bash
# [READ] One request. Exit 0 = nothing changed, 3 = something did.
scripts/gridpane-kb-docs.sh check
```

```bash
# [READ] Full refresh: probe, index into a new dated snapshot, diff, publish.
scripts/gridpane-kb-docs.sh refresh
```

- The wrapper runs `scrape-docs.sh` with its defaults: **10 seconds between live requests**, a count guard against the previous snapshot, and a hard failure when the manifest disagrees with the API's `X-WP-Total`. It copies the new manifest to `skills/gridpane-tooling/references/docs-manifest.json` only when the content actually changed.
- Snapshots and page text live in the gitignored `out/gridpane-docs-cache/<YYYY-MM-DD>/`; the manifest is the only artifact that reaches git. See `skills/gridpane-tooling/references/docs.md`.
- Read the diff, then update the reference files that cite the changed pages. Do not re-verify pages the diff did not report.

## Writing style

- Plain, direct and concise. Tables for command references, numbered lists for workflows.
- Show what output looks like when interpreting it matters (e.g. what "pool seems busy" looks like in the PHP-FPM log).
- No marketing language and no emojis.
- Canadian or US English is fine; stay consistent within a file.

## Commits

- Conventional Commits: `feat(gridpane-api): add site inventory script`, `docs(core): add paths reference`, `chore: lint fixes`.
- One logical change per commit. Update `CHANGELOG.md` under `## Unreleased`.

## Definition of done (per skill)

- [ ] SKILL.md frontmatter valid; description covers the triggers
- [ ] Every command labelled; every [WRITE] has a rollback
- [ ] Every GridPane-specific fact traced in `sources.md`, or listed as unverified
- [ ] References linked from the body and nothing orphaned
- [ ] Scripts pass shellcheck and have `--help`
- [ ] Trigger eval file present, with at least 5 should and 3 should-not prompts
- [ ] `Last verified` date set
- [ ] PLAN.md checkbox ticked
