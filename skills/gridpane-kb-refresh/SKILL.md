---
name: gridpane-kb-refresh
description: >-
  Use to scrape the GridPane Knowledge Base and update the skills that cite it:
  detect drift, index a snapshot, find the files a changed article affects, then
  re-verify.
---

# gridpane-kb-refresh

The GridPane Knowledge Base is the source behind most claims these skills make,
and the skills cite it by URL instead of copying its prose. This skill is the loop
that keeps those citations honest when an article changes: find out whether the KB
moved, index the new state, ask which skill files cite what changed, edit only
those, and re-run the gate.

It is maintainer work on a checkout of `gridpane-ai-skills`. It needs no server,
no SSH and no sudo, and it writes only inside the repository and its gitignored
cache. If the task is a GridPane server, stop here: `gridpane-core` and the
matching server skill are the right entry point.

`references/pipeline.md` holds the command table, exit codes, snapshot layout and
the exact change set, which is everything the steps below rely on.

The checks this loop cannot make — a citation that redirects, a slug the manifest
no longer lists, a new article nothing cites, an article edited after the file
that cites it — belong to `gridpane-citation-audit`, which reads the citation
graph instead of a snapshot diff. Use it when the question is whether the
citations are sound rather than what a refresh changed.

## Prerequisites

- A checkout of `gridpane-ai-skills`; run every command from its root.
- `bash`, `git`, `jq`, `curl`. `pandoc` is optional and only changes how extracted
  article bodies are converted to Markdown.
- For `refresh`, `check` and `search`: network access to `gridpane.com`.
- `skills/gridpane-tooling/references/docs.md` is the CLI contract behind this
  skill. Read it when you need the REST endpoints, the manifest schema or the
  reason a guard fired.

## Workflow

Diagnose before touching a file. Every command carries a label: **[READ]**,
**[WRITE]** or **[DESTRUCTIVE]**.

1. **What do we carry, and has it drifted?** Start with local state. `status`
   reports how many articles are in the committed manifest, what the newest
   snapshot holds, and whether the two disagree.
2. **Has the KB moved?** One request answers it, and the exit code is the answer:
   `0` nothing changed, `3` something did, anything else is a failure.
3. **Index and diff.** `refresh` probes, indexes a dated snapshot, diffs it
   against the previous one, and republishes the committed manifest only where
   content changed.
4. **Which skill files does that touch?** `affected` joins the diff to the KB URLs
   the skills cite and prints `status`, `url` and `file:line`.
5. **Edit only what step 4 named**, then re-stamp that file's `Last verified`.
6. **Trace and gate.** A new or corrected GridPane fact needs a line in
   `skills/gridpane-core/references/sources.md`. Then run `scripts/lint-skills.sh`.
7. **Record it.** Regenerate `KB-CHANGES.md` (`scripts/gridpane-kb-history.sh
   --backfill`) so the history names what moved, add a CHANGELOG entry under
   `## Unreleased`, and make one conventional commit.

An unattended run may do steps 1–4, edit the references they name, and commit. It
must not push, release, or delete a snapshot, and a change that would alter more
than a citation is a human decision.

### 1–2. Diagnose

```bash
# [READ] Ingested, cached, extracted and drift. Local state only, no network.
scripts/gridpane-kb-docs.sh status
```

```bash
# [READ] One request. Exit 0 = nothing changed, 3 = something did.
scripts/gridpane-kb-docs.sh check
```

Exit `3` is work, not failure. Any other non-zero exit stops the loop: the KB is
unreachable, or a guard fired.

### 3. Index the new state

```bash
# [WRITE] Probe, index a dated snapshot, diff it, and publish
# skills/gridpane-tooling/references/docs-manifest.json only where content
# changed. Snapshots stay in the gitignored out/gridpane-docs-cache/.
# Blast radius: one tracked file. Rollback:
#   git checkout -- skills/gridpane-tooling/references/docs-manifest.json
scripts/gridpane-kb-docs.sh refresh
```

A count drop or an `X-WP-Total` mismatch aborts before anything is published, so a
truncated run cannot replace a good manifest. `--offline` rebuilds from the newest
snapshot without a request when you only need to re-publish local state.

### 4. Find the files the change touches

```bash
# [READ] status<TAB>url<TAB>file:line per citation, summary on stderr.
scripts/gridpane-kb-docs.sh affected
```

```bash
# [READ] The same, plus changed articles no skill cites: decide whether one should.
scripts/gridpane-kb-docs.sh affected --all

# [READ] Machine-readable {prev, curr, counts, rows}.
scripts/gridpane-kb-docs.sh affected --json
```

`affected` computes the citation map from the working tree on every run — there is
no index to keep current — so uncommitted edits are already included. It exits `0`
whether or not anything is cited.

### 5–7. Update, trace, gate

Edit only the files step 4 printed. Do not re-verify an article the diff did not
report, and do not restyle a section the change did not justify.

```bash
# [READ] Frontmatter, command labels, relative links, secrets, version agreement.
scripts/lint-skills.sh
```

Then add the CHANGELOG entry and commit. The commit is the record: name the
articles that changed and the files they affected.

## Verify

A refresh is correct when all three hold:

- `status` reports `drift 0 added, 0 removed, 0 changed, 0 title-only` against the
  newest snapshot after `refresh` published.
- `affected` lists a `file:line` for every changed article that a skill cites, and
  every one of those lines is in a file you edited or consciously left alone.
- `scripts/lint-skills.sh` passes, and each edited file's `Last verified` date is
  today's.

## Rollback

- **The manifest.** `git checkout -- skills/gridpane-tooling/references/docs-manifest.json`
  restores the last committed index; the failed snapshot stays in the cache and is
  harmless.
- **A snapshot.** Snapshots are regenerable, so removing one loses nothing but
  history: `scripts/gridpane-kb-docs.sh prune --keep N` prints what it would delete
  and deletes nothing without `--yes`.
- **An edit.** Revert the commit that touched the reference files, not individual
  hunks: the dates and the citation text belong together.

## Gotchas

- **A `modified` timestamp edit is not a change.** The diff compares content
  hashes, so a page that only re-dated itself produces no rows to act on.
- **The hash is over the rendered HTML, not the prose.** A page whose images gain
  `fetchpriority` or new `width`/`height` attributes reports as `changed` while its
  words are identical. Compare the visible text before editing a citation; the
  extracted Markdown from the old and new snapshots is the cheap way to do it.
  `extract --slug SLUG --snapshot OLD` reads an older snapshot.
- **A title-only change has an identical body.** The citation's wording or link
  text may need updating; the prose the skill relies on did not change.
- **`refresh` is deliberately slow.** It waits ten seconds between requests; a
  full run is a few minutes, not a few seconds. Do not lower the delay for a live
  run.
- **`affected` scans `skills/` only, and that is the whole citation set.** README
  and `AGENTS.md` link the KB home (`https://gridpane.com/kb/`), not an article,
  and `CHANGELOG.md` carries no KB link, so there is nothing outside `skills/` to
  check by hand.
- **No KB prose in `skills/`.** The licence question for redistributing article
  text is unresolved (`OPEN-QUESTIONS.md` §"KB text snapshots"). Cite the URL and
  write the fact in our own words.
- **`search` is not part of the loop.** It reads the live KB for one query and
  never touches the cache; use it to find which article a fact came from, not to
  refresh.

## Sources

- `scripts/gridpane-kb-docs.sh` and `skills/gridpane-tooling/scripts/scrape-docs.sh`
  — the implementation this skill drives (read 2026-11-06).
- `skills/gridpane-tooling/references/docs.md` — the CLI contract, guards, manifest
  schema and date model (verified 2026-10-21).
- GridPane KB REST feed — https://gridpane.com/wp-json/wp/v2/kb (387 posts at the
  last full index, 2026-10-21).
- `AGENTS.md` §"Refreshing KB facts" and `plans/implemented/20261106-kb-refresh-workflow.md`
  — the procedure this skill packages.

Last verified: 2026-11-06
