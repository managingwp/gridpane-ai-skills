# KB change diffs

One file per article per reporting interval, rendered by
`scripts/gridpane-kb-history.sh` from the weekly KB report's ledger and the
snapshots it captured. [`KB-CHANGES.md`](../KB-CHANGES.md) is the index; this
directory is the evidence behind it.

Layout: `YYYY/MM/YYYY-MM-DD-<slug>.md`, named for the interval's report date and
the article's WordPress slug.

Each file opens with the title, the change status, the interval, the article URL
and the `file:line` that cites it, then the body its status calls for:

| Status | Body |
|---|---|
| `changed`, text moved | A unified diff of the extracted text, three lines of context, truncated at 64 KB |
| `changed`, hash only | A note that the extracted text is identical and only the rendered markup moved |
| `added` | The extracted size and the URL — never the article's text |
| `removed` | A note that the URL no longer resolves, with its last title |
| `title-only` | The before and after title |

The diff is over text extracted from the KB's REST feed, not the published
HTML, so code blocks and tables may reflow. Treat it as a reading aid: open the
article when a hunk is ambiguous, and never edit a citation from a hunk alone.

Nothing here is written by the scheduled job. Regenerate it from the repository
root with `scripts/gridpane-kb-history.sh --backfill`.
