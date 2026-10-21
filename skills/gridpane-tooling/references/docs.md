# Docs and changelog capture

How the GridPane Knowledge Base is indexed and queried for these skills, and how
the changelog is captured.

## Knowledge Base

`scripts/scrape-docs.sh` is a read-only indexer and lookup tool for the public
KB. Two sources; the REST feed is the default.

- **`--source api` (default)** reads the public WordPress REST feed for the `kb`
  post type: title, slug, link, last-modified time, category terms and the full
  rendered body. All 387 articles come back in four requests.
- **`--source sitemap`** enumerates `/kb/` URLs from the sitemap and fetches each
  page. Kept as a fallback in case the REST route closes.

```bash
# [READ] Build the manifest from the REST feed (all 387 posts).
skills/gridpane-tooling/scripts/scrape-docs.sh \
  --out skills/gridpane-tooling/references/docs-manifest.json
```

```bash
# [READ] Incremental refresh: only posts modified since a date.
skills/gridpane-tooling/scripts/scrape-docs.sh --since 2026-10-01T00:00:00 \
  --out /tmp/kb-since.json
```

```bash
# [READ] Rebuild from the local cache without touching the network.
skills/gridpane-tooling/scripts/scrape-docs.sh --offline \
  --out skills/gridpane-tooling/references/docs-manifest.json
```

```bash
# [READ] Fallback path: enumerate /kb/ URLs from the sitemap.
skills/gridpane-tooling/scripts/scrape-docs.sh --source sitemap --out /tmp/kb.json
```

### Endpoints

| Request | Returns |
|---|---|
| `GET /wp-json/wp/v2/kb?per_page=100&page=N&_fields=slug,link,modified,title,kbcategories,content` | one page of posts with their rendered body |
| `GET /wp-json/wp/v2/kbcategories?per_page=100&page=N&_fields=id,name` | the 107 category terms, so entries carry names instead of ids |
| `GET /wp-json/wp/v2/kb?search=QUERY&per_page=N` | relevance-ordered hits for a single lookup |
| `GET /wp-json/wp/v2/kb?modified_after=DATE&…` | incremental refresh |

The collection response carries `X-WP-Total` and `X-WP-TotalPages`. The script
logs the total and warns when the entry count disagrees, so a truncated run
cannot pass silently.

### Manifest schema

`references/docs-manifest.json` is an object, not an array — the same shape as
`changelog-manifest.json`:

```json
{"schema":2,"source":"api","base":"https://gridpane.com","fetched_at":"2026-10-21T15:31:02Z","count":387,
 "entries":[{"url":"https://gridpane.com/kb/example/","title":"Example","lastmod":"",
             "modified":"2026-10-07T04:34:33","published":"2026-10-06T16:42:34",
             "categories":["Server Caching"],"source":"api","sha256":"…",
             "fetched_at":"2026-10-21T15:31:02Z"}]}
```

| Field | Meaning |
|---|---|
| `schema` | Manifest schema version (`2` since dates became UTC) |
| `source` | `api` or `sitemap` — which path built the manifest |
| `base` | Site root (api source only) |
| `since` | The `modified_after` value, when the run was incremental |
| `fetched_at` | UTC time of the run |
| `count` | Number of entries |
| `entries[].url` | Canonical KB URL |
| `entries[].title` | Post title, entities decoded |
| `entries[].lastmod` | Sitemap `lastmod`; empty for the api source |
| `entries[].modified` | Post modified time in UTC (`modified_gmt`); empty for the sitemap source |
| `entries[].published` | Post published time in UTC (`date_gmt`); empty for the sitemap source |
| `entries[].categories` | `kbcategories` names, or `term-<id>` when the taxonomy fetch failed |
| `entries[].source` | Per-entry source (`api` or `sitemap`) |
| `entries[].sha256` | Hash of the fetched artifact: page HTML (sitemap) or `content.rendered` (api) |
| `entries[].fetched_at` | UTC time the entry was fetched |

Entries are sorted by `url` so diffs stay readable. The `sha256` makes it easy to
see which pages changed between runs.

### Search

Look up an article without building or reading a manifest — one request against
the same REST route:

```bash
# [READ] Search the KB; prints slug, modified, url, title, newest first.
skills/gridpane-tooling/scripts/scrape-docs.sh --search 'fastcgi cache' --limit 5
```

`--json` emits the raw result array for `jq`. `--limit` is the server-side page
size, so it caps by WordPress relevance before the newest-first sort. A query
never touches the cache, so `--search` refuses `--out` and `--offline`; an empty
result logs `no matches` and exits 0. `--search-json FILE` reads a saved response
instead of fetching, which is how the offline test covers this path.

### Extract text

```bash
# [READ] Convert one cached article to text in the gitignored cache.
skills/gridpane-tooling/scripts/scrape-docs.sh \
  --slug cache-warming-gridpane-sitemap-driven-crawler --format markdown
```

`--all` converts every slug present in the cached API pages. pandoc
(`-f html -t gfm`) is used when it is on `PATH`; otherwise a built-in awk/sed
converter drops `script`/`style`/`svg`/`noscript` bodies and turns block tags
into line breaks. Body markup is Elementor output, so the converter alone keeps
inline CSS out of the text. Output is `<snapshot>/<slug>.md` (for example
`out/gridpane-docs-cache/2026-10-21/cache-warming-gridpane-sitemap-driven-crawler.md`)
— never commit it.

### Compare snapshots

```bash
# [READ] What changed between the two most recent snapshots.
skills/gridpane-tooling/scripts/scrape-docs.sh --diff
```

Output is TSV: `status<TAB>url<TAB>old_modified<TAB>new_modified<TAB>title`, one
line per change, where `status` is `added`, `removed`, `changed` (body hash
differs) or `title` (title differs, body identical). `--json` emits
`{prev, curr, added, removed, changed, title_changed, counts}`, and a one-line
summary goes to stderr. `--diff PREV` compares against a named snapshot
directory instead of the automatically detected previous one. A change to
`modified` alone is not reported — a timestamp edit with identical text is not
worth re-reading an article for. The command is read-only: no network, no
writes, and it exits 0 even when every entry changed.

### Politeness and provenance

- Descriptive User-Agent, `--retry 3`, a **10 s delay** between live requests
  (a live run refuses `--delay` below 10; `--allow-fast` exists for fixture
  runs), `--limit` for partial runs, and a page size capped at 100.
- `--dry-run` prints the request URL(s) and exits without fetching, so you can
  see what a run would do before it touches the network.
- `robots.txt` disallows only `/wp-admin/`. The REST responses carry
  `X-Robots-Tag: noindex`, which is the site's search-indexing preference, not a
  prohibition on reading public content.
- **Only the manifest is committed.** Raw JSON, HTML and extracted text stay in
  the gitignored `out/gridpane-docs-cache/`; no GridPane page text is rehosted.
- Every live run writes a **dated snapshot**:
  `out/gridpane-docs-cache/<YYYY-MM-DD>[-N]/` with its `manifest.json`, and
  `out/gridpane-docs-cache/latest` points at the newest one. An existing
  snapshot is never written into, and an aborted run leaves its directory
  without `manifest.json` (later runs ignore it). `--offline` reads the newest
  snapshot, or the one named by `--snapshot`.
- Measured 2026-10-21: 387 posts, 107 categories, six requests for a full build,
  ~1.9 MB per 100-post page with bodies, ~27 KB metadata-only, ~1 min 45 s wall
  at the 10 s delay.

### Guards

A refresh refuses to produce a bad manifest:

| Guard | Behaviour | Override |
|---|---|---|
| Entry count | Aborts when the count is below 90% of the previous snapshot | `--force` |
| `X-WP-Total` | Aborts when the manifest count disagrees with the API's total | `--partial` |
| Response shape | Aborts on a non-array JSON body or a body over 8 MB | none |
| Concurrency | Aborts when another run holds `<cache>/.lock` (`flock`) | none |
| Delay | Refuses `--delay` below 10 s on a live run | `--allow-fast` (fixtures only) |
| Snapshots | Never writes into an existing snapshot directory | none |


### Gotchas

- **The REST route is public today, not contractual.** If `--source api` starts
  returning 401 or 404, fall back to `--source sitemap` and record the change in
  the repo's `OPEN-QUESTIONS.md` rather than patching around it.
- **Do not double-unescape.** Bodies arrive entity-encoded with escaped markup
  inside `<pre>` (`&lt;`, `2&gt;&amp;1`). Decode once, and decode `&amp;` last,
  or `&amp;#8217;` turns into a second entity.
- **REST `modified`/`date` are site-local (UTC-4), not UTC.** Use
  `modified_gmt`/`date_gmt` — they match the sitemap `lastmod` and the page's
  `article:modified_time`. The manifest stores only the UTC values.
- **`X-WP-Total` is the cheap drift check.** One request with `-o /dev/null -D -`
  tells you whether 387 is still the right number, with no crawl.

## Changelog

The GridPane changelog at `https://roadmap.gridpane.com/changelog` is a
JavaScript SPA (Upvoty), but it reads a **public JSON API** — so no browser is
needed:

- `GET https://core-api.upvotyfeedback.com/public/projects/roadmap.gridpane.com`
  returns the portal config: `owner`, project `id`, and an `accountSession`
  access token.
- `GET {api}/{owner}/projects/{id}/changelog?perPage=N&page=P` with
  `Authorization: Bearer portal_<accessToken>` returns
  `{items, total, perPage, page, pages}`.

`scripts/scrape-changelog.sh` (curl + jq) resolves the portal, pages through the
API, and writes `references/changelog-manifest.json` — a digest of
`id`/`title`/`published_at`/`tags` per entry, newest first:

```bash
# [READ] Build the changelog digest (all pages).
skills/gridpane-tooling/scripts/scrape-changelog.sh \
  --out skills/gridpane-tooling/references/changelog-manifest.json
```

```bash
# [READ] Offline: build from a saved page fixture (no network).
skills/gridpane-tooling/scripts/scrape-changelog.sh \
  --changelog-json fixture-page.json --out /tmp/changelog.json
```

Notes:

- The digest carries only metadata (title, date, tags, stable entry `id`); the
  full entry text stays in the source.
- The SPA exposes **no per-entry deep link** (verified 2026-10-19: navigating to
  `/changelog/{id}` renders the feedback feed, not the entry). The manifest's
  `source` is the changelog index; entries are identified by `id`.
- The API token is per-session and fetched at runtime; it is never stored.

## Tests

`tests/scripts/test_scrape_docs.sh` is fully offline: it builds a fixture
sitemap, HTML cache, API page and category map, then asserts the manifest
envelope and per-entry fields for both sources, the URLs `--dry-run` builds
(including `modified_after`), one-request search from a saved response
(ordering, entity decoding, `no matches`, bad flag combinations) and text
extraction (command text kept, inline CSS and entities dropped).
`tests/scripts/test_scrape_changelog.sh` runs the changelog scraper against a
fixture page and asserts fields, dedupe, ordering and `--help`. Neither touches
the network.

## Sources

- `skills/gridpane-tooling/scripts/scrape-docs.sh`,
  `scripts/scrape-changelog.sh` (implementation).
- `tests/scripts/test_scrape_docs.sh`,
  `tests/scripts/test_scrape_changelog.sh` (offline tests).
- GridPane KB REST feed — https://gridpane.com/wp-json/wp/v2/kb
  (checked 2026-10-21: `X-WP-Total: 387`, which matches the sitemap's 387 `/kb/`
  URLs).
- GridPane KB categories — https://gridpane.com/wp-json/wp/v2/kbcategories
  (checked 2026-10-21: 107 terms).
- GridPane sitemap — https://gridpane.com/sitemap.xml
- GridPane changelog (Upvoty SPA; public JSON API) — https://roadmap.gridpane.com/changelog

Last verified: 2026-10-21
