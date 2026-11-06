# Citation checks

What `scripts/gridpane-kb-docs.sh audit` checks, what each finding means, and what
it costs. Read this when a finding needs interpreting, or when the command
disagrees with what you see in the tree.

## The four offline checks

| Check | Reads | Finding | Exit |
|---|---|---|---|
| `unknown` | the manifest, `skills/**/*.md` | A cited slug the manifest does not list | `3` |
| `uncited-new` | the newest two snapshots, the citations | An article added between them that no skill cites | advisory |
| `stale` | manifest `modified`, each citing file's last commit | The article was modified after the file was last committed | advisory |
| `coverage` | the manifest, the citations | Distinct articles cited, per skill directory | advisory |

`unknown`, `moved` and `down` are unsound citations: the URL does not point at
the article the skill means. `uncited-new` and `stale` are advisory — a new
article is not a defect, and a stale hit is a prompt to re-read — so they do not
change the exit code.

The scan covers `skills/**/*.md` and skips fenced code blocks. A URL in an example
is an illustration, not a citation.

## The probe

`--probe` adds two more findings, and only for `unknown` URLs:

| Check | Condition | Finding |
|---|---|---|
| `moved` | `301`, `302`, `303`, `307` or `308` | The `location` header, without a trailing slash |
| `down` | `404`, `410`, or another non-2xx/3xx | The status code |

A URL in the manifest is sound by construction, so it is never requested. The
cost is one request per `unknown` finding, ten seconds apart: four on the day the
audit landed, zero once those four were fixed. A redirect to the same slug (a
trailing slash) is not a finding.

`--probe-file FILE` reads a saved `{url: {status, location}}` map instead of
fetching, which is how the offline test covers the path. `--allow-fast` drops the
delay; it is for fixtures, never a live run.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | The citation graph is sound |
| `3` | `unknown`, `moved` or `down` found at least one unsound citation |
| `2` | Usage error |
| `1` | Failure: no manifest, or an unreadable probe fixture |

Advisory findings leave the code at `0`.

## JSON shape

```json
{"manifest":{"path":"skills/gridpane-tooling/references/docs-manifest.json","articles":389},
 "snapshots":{"prev":"2026-10-21-3","curr":"2026-11-06"},
 "counts":{"articles":389,"cited":71,"references":172,"files":26,
           "unknown":0,"uncited_new":0,"stale":0,"moved":0,"down":0},
 "unknown":[{"url":"https://gridpane.com/kb/example",
             "references":[{"file":"skills/x/SKILL.md","line":4}]}],
 "uncited_new":[{"url":"https://gridpane.com/kb/new","title":"New",
                 "modified":"2026-11-01T00:00:00"}],
 "stale":[{"url":"https://gridpane.com/kb/old","modified":"2026-11-01",
           "file":"skills/x/SKILL.md","line":4,"committed":"2026-10-01"}],
 "coverage":[{"skill":"gridpane-core","cited":58,"articles":389}],
 "moved":[{"url":"https://gridpane.com/kb/old","status":301,
           "location":"https://gridpane.com/kb/new","references":[]}],
 "down":[{"url":"https://gridpane.com/kb/gone","status":404,"references":[]}]}
```

`counts.cited` is distinct URLs, `references` the `file:line` rows and `files` the
distinct citing files. `snapshots` is `null` when the cache has fewer than two
completed snapshots, and `uncited_new` is then empty.

## The `--ignore` rule

`--ignore URL` is for a citation you have looked at and consciously accept: a KB
page that is not an article, or a URL that is deliberately outside the manifest.
It is repeatable, compares without a trailing slash, and removes the URL from
every finding while keeping it in the citation counts.

An ignore is a command-line flag, never stored state. Use it in a one-off run, or
in a CI job with a documented reason; do not add one to hide a redirect you have
not fixed.
