---
name: gridpane-example
description: >-
  TEMPLATE ONLY. Replace this with a real skill. Use when <situation the user is
  in>, <second situation>. Covers <what it does> for GridPane servers. Do not use
  for <sibling case handled elsewhere>.
---

# gridpane-example

One paragraph of purpose. Say what the skill does and the outcome the agent
should reach. Name the sibling skill when another is a better fit.

> Folder name must equal the `name` in the frontmatter. Rename the folder and
> the frontmatter together. Keep the description at or under 1024 characters.

## Prerequisites

- GridPane server access needed (root or sudo over SSH, or a site system user).
- Load `gridpane-core` first: it defines paths, `gp` conventions and the safety
  protocol the rest of this skill relies on.
- Anything else the agent must have before it starts.

## Workflow

Diagnose before you act. Every command below carries a label: **[READ]**,
**[WRITE]** or **[DESTRUCTIVE]** (see `gridpane-core/references/safety.md`).

1. **Establish the symptom.** Run the read-only checks that pin down what is
   actually happening.
2. **Narrow it down.** Use the checks that distinguish the likely causes.
3. **Decide and propose.** If a change is needed, present it with the
   confirmation template before running it.

```bash
# [READ] Describe what this command shows and why it matters.
example-read-command --flag value
```

## Verify

How to confirm the change had the intended effect. Prefer an observable check
(response code, header, log line) over "it looked fine".

## Rollback

For every [WRITE] step, state the exact command that reverses it. Config edits
restore from the `.bak-<timestamp>` copy taken first.

## Gotchas

- GridPane-specific traps: files that `gp` regenerates, per-site vs server-wide
  blast radius, cache layers that mask a change.

## Sources

- <URL> (checked YYYY-MM-DD)

Last verified: YYYY-MM-DD
