# Docs and changelog capture

How the GridPane Knowledge Base is indexed for these skills, and the state of the
changelog capture.

## Knowledge Base

`scripts/scrape-docs.sh` is a read-only indexer for the public KB:

```bash
# [READ] Build the manifest from the live sitemap (default: all /kb/ pages).
skills/gridpane-tooling/scripts/scrape-docs.sh \
  --out skills/gridpane-tooling/references/docs-manifest.json
```

```bash
# [READ] Rebuild from the local cache without touching the network.
skills/gridpane-tooling/scripts/scrape-docs.sh --offline \
  --out skills/gridpane-tooling/references/docs-manifest.json
```

- Source of truth: `https://gridpane.com/sitemap.xml`, filtered to `/kb/` URLs
  (387 at the time of writing). `robots.txt` allows it (only `/wp-admin/` is
  disallowed).
- The script fetches with a descriptive User-Agent, `--retry 3`, a `--delay`
  (default 1s) and a `--limit`. Raw HTML and optional Markdown (via `pandoc`)
  stay in the gitignored cache (`out/gridpane-docs-cache/`); **only the manifest
  is committed** — no GridPane page text is rehosted.
- `--offline` reads pages from the cache, so tests and re-runs never hit the
  network.

### Manifest schema

`references/docs-manifest.json` is a JSON array; one object per `/kb/` page:

```json
{"url":"https://gridpane.com/kb/example/","title":"Example | GridPane","lastmod":"2026-01-02T03:04:05+00:00","fetched_at":"2026-10-14T11:09:19Z","sha256":"…"}
```

| Field | Meaning |
|---|---|
| `url` | Canonical KB page URL |
| `title` | Page `<title>` |
| `lastmod` | Sitemap `lastmod` (may be empty) |
| `fetched_at` | UTC time the page was fetched |
| `sha256` | SHA-256 of the fetched HTML, to detect change between runs |

Refresh on demand and update `Last verified`; the `sha256` makes it easy to see
which pages changed.

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

`tests/scripts/test_scrape_docs.sh` runs the KB scraper `--offline` against a
fixture sitemap and cache and asserts the manifest fields, entry count and `/kb/`
filtering. `tests/scripts/test_scrape_changelog.sh` runs the changelog scraper
against a fixture page and asserts fields, dedupe, ordering and `--help`. Neither
touches the network.

## Sources

- `skills/gridpane-tooling/scripts/scrape-docs.sh`,
  `scripts/scrape-changelog.sh` (implementation).
- `tests/scripts/test_scrape_docs.sh`,
  `tests/scripts/test_scrape_changelog.sh` (offline tests).
- GridPane sitemap — https://gridpane.com/sitemap.xml
- GridPane changelog (Upvoty SPA; public JSON API) — https://roadmap.gridpane.com/changelog

Last verified: 2026-10-19
