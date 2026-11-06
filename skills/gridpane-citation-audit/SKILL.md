---
name: gridpane-citation-audit
description: >-
  Use to audit the skills' GridPane KB citations: dead or renamed links, new
  articles nothing cites, and facts that changed after a file was last verified.
  Not the KB update loop.
---

# gridpane-citation-audit

The skills make GridPane claims by citing KB URLs instead of copying prose, so a
citation is the load-bearing part of the fact. This skill asks whether those
citations are still sound: a link that redirects or 404s, a cited slug the
manifest does not know, a new article nothing cites, or an article edited after
the file that relies on it. It is state-driven and corpus-wide, and it writes
nothing.

It is not the KB update loop. `gridpane-kb-refresh` answers "what changed, and
which files must I edit now" from a snapshot diff; this skill asks "are the
citations themselves sound" and can find rot with no snapshot at all. When the
task is to fetch, index or re-publish the KB, use that skill instead.

This is maintainer work on a checkout of `gridpane-ai-skills`. It needs no server,
no SSH and no sudo, and it changes nothing outside the files you edit.

`references/checks.md` holds the four checks, the probe cost model, the exit
codes and the JSON shape.

## Prerequisites

- A checkout of `gridpane-ai-skills`; run every command from its root.
- `bash`, `git`, `jq`. `curl` only for `--probe`.
- The committed manifest is required: `unknown`, `stale` and `coverage` read it.
  `uncited-new` also needs two completed snapshots in the gitignored cache.
- `skills/gridpane-tooling/references/docs.md` is the CLI contract behind the
  command. Read it when you need the manifest schema or the date model.

## Workflow

Diagnose before editing. Every command carries a label: **[READ]**, **[WRITE]** or
**[DESTRUCTIVE]**.

1. **Run the offline audit.** Four checks, no network: `unknown`, `uncited-new`,
   `stale`, `coverage`. Exit `3` means an unsound citation; `0` means the
   citation graph is sound.
2. **Read the findings in order of certainty.** `unknown` is a fact — the
   manifest does not list that slug. `stale` is a prompt, not a verdict.
3. **Probe the unknown URLs.** `--probe` requests only the URLs the manifest does
   not know, so it costs one request per unknown finding. A `301` names the new
   URL; a `404` means the citation is dead.
4. **Fix what is objectively wrong.** A redirect or a 404 has one correct answer.
   Replace the URL and keep the link text and the surrounding sentence.
5. **Trace and gate.** A corrected citation updates its row in
   `skills/gridpane-core/references/sources.md`. Re-stamp the edited file's
   `Last verified` if it carries one. Then run `scripts/lint-skills.sh`.
6. **Re-run the audit.** It should be clean, and the counts belong in the commit.

### 1–3. Diagnose

```bash
# [READ] Four offline checks over the committed manifest and skills/**/*.md.
scripts/gridpane-kb-docs.sh audit
```

```bash
# [READ] Machine-readable {counts, unknown, uncited_new, stale, coverage, ...}.
scripts/gridpane-kb-docs.sh audit --json
```

```bash
# [READ] The network half: one request per unknown URL, ten seconds apart.
scripts/gridpane-kb-docs.sh audit --probe
```

`--probe` never requests a URL the manifest lists: a known URL is sound by
construction. That is what keeps the command cheap enough for CI — four requests
on the day this skill was written, zero once those four were fixed.

### 4. Fix what is objectively wrong

```bash
# [READ] The exact files and lines behind every finding.
scripts/gridpane-kb-docs.sh audit --json \
  | jq -r '(.moved[], .down[], .unknown[]) | .references[] | "\(.file):\(.line)"' \
  | sort -u
```

Edit those lines only. A redirect's target is the new URL; the claim did not
change, so the link text and the sentence stay as they are.

### 5. Trace and gate

```bash
# [READ] Frontmatter, command labels, relative links, secrets, version agreement.
scripts/lint-skills.sh
```

### 6. Re-run

```bash
# [READ] Clean means unknown, moved and down are all 0.
scripts/gridpane-kb-docs.sh audit --probe
```

## Verify

- `audit` exits `0`, and `unknown`, `moved` and `down` are all `0`.
- Every file a finding named was edited or consciously left alone, and the reason
  is in the commit message.
- `scripts/lint-skills.sh` passes.
- Each edited file's last commit is today (`git log -1 --format=%cs -- FILE`),
  which is what keeps the `stale` check quiet.

## Rollback

- **A citation edit.** `git checkout -- FILE` reverts one file. The URL, the link
  text and the `Last verified` date belong together, so revert the commit rather
  than individual hunks.
- **An `--ignore`.** It is a flag, not stored state: drop it and the finding comes
  back. Only add one where the URL is deliberately outside the manifest, and say
  why in the commit or the CI job.
- **The audit itself.** It writes nothing, so there is nothing to undo.

## Gotchas

- **A redirect is not always a rename.** A `301` to the same slug with a trailing
  slash is normalisation and the audit ignores it. A `301` to a different slug is
  a rename, and the citation is wrong.
- **`unknown` is not the same as dead.** A cited URL absent from the manifest that
  answers `200` may be a KB page that is not an article, or one added after the
  last index. Probe it before editing, and `--ignore` it only if it is deliberate.
- **`stale` is a prompt, not a verdict.** An article edited after the citing
  file's last commit may still say exactly what the skill claims. Read the
  article and the sentence before changing either.
- **`uncited-new` is an opportunity, not a defect.** A new article deserves a
  citation only when a skill makes a claim it should source. A release note or a
  product announcement usually does not.
- **Fenced code blocks are skipped.** A URL inside an example is an illustration,
  not a citation, so the audit will not report it and a fix must not "correct" it.
- **`Last verified` is not the staleness signal.** Only some files carry one, so
  the check uses the citing file's last commit and falls back to the date line
  when git cannot answer.
- **The audit never refreshes.** A slug missing from the manifest may simply be
  newer than the last snapshot; `gridpane-kb-refresh` fixes that, not this skill.

## Recording "no change"

When the audit is clean there is nothing to edit and no CHANGELOG entry. Record
the counts in the commit that follows the work they justified, or in the plan
phase that asked for the run. Do not invent a change to make the audit look
useful.

## Sources

- `scripts/gridpane-kb-docs.sh` — the implementation this skill drives (read
  2026-11-06).
- `skills/gridpane-tooling/references/docs.md` — the CLI contract, manifest schema
  and date model.
- `references/checks.md` — the four checks, the probe cost model, exit codes and
  the JSON shape.

Last verified: 2026-11-06
