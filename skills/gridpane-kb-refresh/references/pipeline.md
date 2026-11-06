# Pipeline reference

The facts the refresh loop depends on: commands, exit codes, what a snapshot is,
what counts as a change, and what the guards refuse. The deeper internals — REST
endpoints, manifest schema, category mapping, the date model — live in
`skills/gridpane-tooling/references/docs.md`; this file restates only what the loop
needs, so the skill stands alone when it is installed without its sibling.

## Commands

`scripts/gridpane-kb-docs.sh` is the entry point. It wraps
`skills/gridpane-tooling/scripts/scrape-docs.sh`, which does the fetching, diffing
and extraction; no URL or snapshot logic is duplicated in the wrapper.

| Command | Network | What it does |
|---|---|---|
| `status` | no (`--remote`: one request) | Ingested, cached, extracted and drift counts, the newest article, the snapshot list |
| `check` | one request | Exit `0` unchanged, `3` changed; built for automation |
| `refresh` | probe + up to six requests when it indexes | Probe, index a dated snapshot, diff it, publish the manifest |
| `affected [PREV]` | no | The `file:line` in `skills/` that cites each changed article |
| `list` | no | Articles in the newest snapshot (`--filter TEXT`, `--limit N`) |
| `search QUERY` | one request | Live KB lookup, relevance-ordered; never touches the cache |
| `diff [PREV]` | no | Added, removed, changed and title-only rows between two snapshots |
| `extract` | no | One article or all of them as text or Markdown (`--slug`, `--all`, `--format`) |
| `prune` | no | Remove old snapshots (`--keep N`); dry run unless `--yes` |

Flags that matter to the loop: `--json` (`status`, `check`, `refresh`, `list`,
`search`, `diff`, `affected`, `prune`), `--offline` (`refresh` rebuilds from the
newest snapshot), `--all` (`affected` also lists changed articles nothing cites),
`--skills DIR` (`affected` scans another tree, used by its test), `--force`
(`refresh` accepts a count drop; do not use it to get past a guard you have not
explained).

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Done, or nothing to do |
| `3` | `check` only: the KB moved |
| `2` | Usage error |
| `1` | Failure: unreachable KB, a guard fired, no snapshots to read |

A bare invocation prints usage and exits `2`.

## Snapshots

`out/gridpane-docs-cache/<YYYY-MM-DD>[-N]/` — one directory per completed run,
suffixed `-N` when a day gets several. The cache is gitignored; it is history, not
an artefact.

Inside a snapshot:

| File | Contents |
|---|---|
| `manifest.json` | The run's index: `count`, `fetched_at`, and one entry per article (url, slug, title, `sha256`, `modified`, `published`, categories) |
| `api-page-N.json` | Raw REST pages (the `api` source) |
| `api-kbcategories-N.json` | Raw category terms, so entries carry names rather than ids |
| `<slug>.md` | Extracted article text, written only by `extract` |

Also in the cache root: `latest`, a pointer to the published snapshot, and
`last-run.json`, the cursor `--since-last` and the probe compare against.

A directory with no `manifest.json` is an aborted run. It is ignored by every
command that reads snapshots and is safe to delete.

## What counts as a change

The diff compares two snapshots entry by entry and reports four statuses:

| Status | Condition |
|---|---|
| `added` | In the new snapshot, not in the old |
| `removed` | In the old snapshot, not in the new |
| `changed` | Present in both, different `sha256` (the body differs) |
| `title` | Present in both, same body hash, different title |

A change to `modified` alone is **not** reported: a timestamp edit with identical
text is not worth re-reading an article for. That is why "the KB moved" and "an
article changed" are different questions, answered by `check` and `diff`.

`changed` means the `sha256` differs, and that hash is taken over the article's
rendered HTML. Image attributes, wrapper markup or an editor re-render change the
hash without changing a word — so `changed` is a candidate, not a verdict. Read
the body before editing a citation.

## The counts

| Count | Means |
|---|---|
| `ingested` | Articles in the committed manifest — what the skills actually carry |
| `cached` | Articles in the newest completed snapshot |
| `extracted` | `.md` files in that snapshot |
| `drift` | Manifest versus snapshot: added, removed, changed, title-only |

`drift 0 0 0 0` after a `refresh` is the proof that the published manifest matches
the snapshot that was just indexed.

## Guards

- **Politeness.** Ten seconds between live requests by default. `refresh` is a few
  minutes by design; `--allow-fast` exists for fixtures only.
- **Count guard.** A drop against the previous snapshot aborts the run unless
  `--force`, so a truncated crawl cannot replace a good manifest.
- **Hard failure on disagreement.** The REST feed's `X-WP-Total` is compared with
  the entry count; a mismatch fails the run rather than publishing a partial index.
- **Publish only on change.** The manifest keeps an entry's `fetched_at` when its
  `sha256` and title are unchanged, so the committed file moves only where the KB
  actually moved.
- **`prune` is the only destructive command.** It skips the newest snapshot and the
  one `latest` points at, refuses `--keep 0`, and deletes nothing without `--yes`.

## `affected` output

Plain: one TSV row per citation, `status<TAB>url<TAB>file:line`, sorted by status
then URL; a summary goes to stderr (`1 changed, 0 cited, 0 references in 0 files
(prev..curr)`).

`--json`:

```json
{"prev":"2026-01-01","curr":"2026-01-02",
 "counts":{"changed":4,"cited":3,"references":4,"files":1},
 "rows":[{"status":"changed","url":"https://gridpane.com/kb/a","file":"skills/x/SKILL.md","line":1}]}
```

`counts.changed` is every article in the diff (all four statuses), `cited` the
distinct ones at least one skill references, `references` the number of
`file:line` rows, and `files` the distinct files. With `--all`, uncited articles
appear with `"file": null, "line": null` and a `-` in the plain output.

The scan covers `skills/**/*.md`, which is the whole citation set: `README.md` and
`AGENTS.md` link the KB home rather than an article, and `CHANGELOG.md` links no
KB page at all.
