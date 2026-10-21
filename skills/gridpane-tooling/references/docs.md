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
{"source":"api","base":"https://gridpane.com","fetched_at":"2026-10-21T15:31:02Z","count":387,
 "entries":[{"url":"https://gridpane.com/kb/example/","title":"Example","lastmod":"",
             "modified":"2026-10-07T00:34:33","categories":["Server Caching"],
             "source":"api","sha256":"…","fetched_at":"2026-10-21T15:31:02Z"}]}
```

| Field | Meaning |
|---|---|
| `source` | `api` or `sitemap` — which path built the manifest |
| `base` | Site root (api source only) |
| `since` | The `modified_after` value, when the run was incremental |
| `fetched_at` | UTC time of the run |
| `count` | Number of entries |
| `entries[].url` | Canonical KB URL |
| `entries[].title` | Post title, entities decoded |
| `entries[].lastmod` | Sitemap `lastmod`; empty for the api source |
| `entries[].modified` | Post modified time; empty for the sitemap source |
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
inline CSS out of the text. Output is
`out/gridpane-docs-cache/<slug>.md` — never commit it.

### Politeness and provenance

- Descriptive User-Agent, `--retry 3`, a `--delay` (default 1s) between requests,
  `--limit` for partial runs, and a page size capped at 100.
- `--dry-run` prints the request URL(s) and exits without fetching, so you can
  see what a run would do before it touches the network.
- `robots.txt` disallows only `/wp-admin/`. The REST responses carry
  `X-Robots-Tag: noindex`, which is the site's search-indexing preference, not a
  prohibition on reading public content.
- **Only the manifest is committed.** Raw JSON, HTML and extracted text stay in
  the gitignored `out/gridpane-docs-cache/`; no GridPane page text is rehosted.
- Measured 2026-10-21: 387 posts, 107 categories, six requests for a full build,
  ~1.9 MB per 100-post page with bodies, ~27 KB metadata-only, ~50 s wall.

### Gotchas

- **The REST route is public today, not contractual.** If `--source api` starts
  returning 401 or 404, fall back to `--source sitemap` and record the change in
  the repo's `OPEN-QUESTIONS.md` rather than patching around it.
- **Do not double-unescape.** Bodies arrive entity-encoded with escaped markup
  inside `<pre>` (`&lt;`, `2&gt;&amp;1`). Decode once, and decode `&amp;` last,
  or `&amp;#8217;` turns into a second entity.
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
