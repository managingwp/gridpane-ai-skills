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
JavaScript single-page app backed by **Upvoty**. `curl` returns only the app
shell for every path, so a plain fetch cannot capture it. Capturing it needs one
of:

- the Upvoty board/API identifier (then query the Upvoty API directly), or
- an RSS/export from the roadmap, or
- a headless browser in the scraper to render the SPA.

This is deferred pending the board/API details; tracked in `OPEN-QUESTIONS.md`.
Do not add a headless-browser dependency until that is agreed.

## Tests

`tests/scripts/test_scrape_docs.sh` runs the scraper `--offline` against a
fixture sitemap and cache and asserts the manifest fields, entry count and `/kb/`
filtering. It never touches the network.

## Sources

- `skills/gridpane-tooling/scripts/scrape-docs.sh` (implementation).
- `tests/scripts/test_scrape_docs.sh` (offline test).
- GridPane sitemap — https://gridpane.com/sitemap.xml
- GridPane changelog (Upvoty SPA) — https://roadmap.gridpane.com/changelog

Last verified: 2026-10-14
