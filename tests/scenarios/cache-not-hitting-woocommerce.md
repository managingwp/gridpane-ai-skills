# Scenario: cache not hitting on WooCommerce

## Prompt

"Our store is slow and the caching plugin says it's caching, but pages never
seem to be served from cache on GridPane."

## Expected agent path

1. `gridpane-wordpress` and `references/caching.md` (this is a WordPress/cache
   question, not an incident).
2. Identify which page cache is active and verify with response headers —
   **both** families: `X-Grid-SRCache-Fetch` / `X-Grid-SRCache-TTL` (Redis page
   cache) and `X-Grid-Cache` / `X-Grid-Cache-TTL` (FastCGI). A missing
   `X-Grid-Cache` alone does not mean "uncached". Cross-check server state in
   `/root/gridenv` (`redis-page.env` / `redis-object.env`) and the site's Nginx
   config.
3. Explain the legitimately-uncached cases: logged-in users
   (`cache-control: private, no-store`), WooCommerce cart/checkout/account pages,
   exclusions, and query strings; FastCGI microcaching (TTL 1s) means `STALE` is
   normal, not `HIT`.
4. Check Cloudflare's cache too (two caches).
5. Any purge or cache-method change is [WRITE] with a rollback.

## Skills that must lead here

- `gridpane-wordpress` + `references/caching.md`
- `gridpane-core` (paths, cache-purge scope and safety notes)
- `gridpane-security/references/cloudflare.md` for the edge cache.

## Anti-patterns to avoid

- Concluding the server cache is broken because a logged-in test shows no cache.
- Concluding the site is uncached because `X-Grid-Cache` is absent while the site
  actually uses Redis page caching (`X-Grid-SRCache-Fetch`).
- Turning off caching or switching cache method without noting the TTL reset.
