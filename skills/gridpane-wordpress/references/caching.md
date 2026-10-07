# Caching on GridPane

GridPane has layered caches. Decide which layer is in play before concluding a
change "didn't work".

## The layers

| Layer | What it holds | Where it is configured |
|---|---|---|
| Nginx FastCGI page cache | Full HTML pages | Site customizer > Caching, or `gp site … -fastcgi-cache` |
| Redis page cache | Full HTML pages (alternative to FastCGI) | Site customizer, or `gp site … -redis-cache` |
| Redis object cache | WordPress database query results | Site customizer > Object Caching, or `gp site … -redis-object-caching` |
| CDN / Cloudflare | Full responses at the edge | Cloudflare dashboard |
| Browser | Full responses | Browser cache |

Nginx uses FastCGI page caching; the alternative page cache is Redis page
caching. **Object caching is separate from page caching.** On OpenLiteSpeed the
page cache is LSCache / the LiteSpeed Cache plugin, not FastCGI.

## Which page cache is active?

There is no single "which is on" command in the KB; determine it from the site
customizer's Caching tab, or from the response headers (below) and the site's
cache config. Do not guess and reconfigure blindly — changing the page cache
method requires resetting the TTL manually when switching from Redis to FastCGI.

## Verify hits (response headers)

Load the site **in an incognito window** (logged-in sessions bypass cache) and
inspect the response headers:

- `X-Grid-Cache: HIT | MISS | BYPASS | STALE`
  - `HIT` — served from cache.
  - `MISS` — not cached yet; reload should give `HIT`.
  - `BYPASS` — this page is excluded and will never be cached.
  - `STALE` — the browser's copy expired; still served from the server cache and
    refreshed in the background. Common with FastCGI.
- `X-Grid-Cache-TTL: <seconds>` — the cache TTL.

```bash
# [READ] Check cache headers from the server (use a cache-busting UA if needed).
curl -sSI https://example.com | grep -i 'x-grid-cache'
```

FastCGI uses **microcaching**: default TTL is **1 second**. Getting `HIT` with
FastCGI is hard because of that; `STALE` still means the server cache is working.
Redis page caching suits mostly-static content; FastCGI suits high-concurrency or
frequently-changing content.

While logged in, the site sends `cache-control: private, no-store` and is not
cached.

## Purge

```bash
# [WRITE] Clear every cache for one site (page, object, opcode).
# Blast radius: site example.com only. Rollback: caches rebuild on next visit.
# Confirm before running.
gp fix cached example.com
```

```bash
# [WRITE] Clear caches for EVERY site on the server.
# Blast radius: all sites. Confirm before running.
gp fix cached
```

Equivalent UI actions: the site customizer's flush button (one site, or all
caches), and, in WordPress, the admin bar > Object Cache > Flush Cache, or the
Redis Object Cache plugin's Flush Cache button.

The cache and its purging are managed by the **GridPane Nginx Helper** plugin (a
fork of rtCamp's Nginx Helper), auto-configured with the correct caching and
purge methods via `wp-config.php`, which is why those settings cannot be
misconfigured in the UI.

## "Cache isn't working" — common causes

1. **You are logged in.** Logged-in requests set `cache-control: private,
   no-store` and are never cached. Test in incognito.
2. **The page is excluded.** Check GridPane's default cache exclusions and any
   per-page exclusions.
3. **`BYPASS` in the header.** The path or a cookie/query string triggered an
   exclusion.
4. **WooCommerce / dynamic pages.** Cart, checkout and account pages legitimately
   bypass cache. See the WooCommerce KB article.
5. **Query strings.** Some query strings force an uncached response; there is a
   KB article on removing specific query strings so the cached version loads.
6. **FastCGI TTL is 1 second.** You will often see `STALE`, not `HIT`; that is
   expected and healthy.
7. **A CDN in front.** Cloudflare may serve its own cached copy; check Cloudflare
   caching too.

## Changing the cache

All are [WRITE], per site:

```bash
# [WRITE] Enable FastCGI page cache with a 1s TTL.
gp site example.com -fastcgi-cache -ttl 1
```

```bash
# [WRITE] Enable Redis page cache with a longer TTL (seconds).
gp site example.com -redis-cache -ttl 2592000
```

```bash
# [WRITE] Disable page caching.
gp site example.com -cache-off
```

```bash
# [WRITE] Toggle Redis object caching.
gp site example.com -redis-object-caching on
```

Rollback for each: reverse the toggle (`-cache-off`, or `-redis-object-caching
off`), or re-enable the previous method and restore its TTL.

## Gotchas

- **Switching page cache method resets the TTL.** When moving from Redis page
  cache to FastCGI, set the TTL manually afterwards.
- **Object cache plugin missing?** Toggle Object Caching off then on in the UI to
  reinstall the Redis Object Cache plugin.
- **Purge is server-wide without a site URL.** `gp fix cached` hits everything.
- **Excluding pages:** use the supported exclusions (Nginx Helper or PHP-header
  exclusions), not hand-invented Nginx cache variables.

## Sources

- FastCGI Page Caching — https://gridpane.com/kb/using-gridpane-nginx-fastcgi-page-caching/
- Redis Page Caching — https://gridpane.com/kb/using-gridpane-nginx-redis-page-caching/
- Redis Object Caching — https://gridpane.com/kb/using-gridpane-redis-object-caching/
- Clear all caches (all methods) — https://gridpane.com/kb/how-to-clear-your-website-caches-all-methods/
- Default cache exclusions — https://gridpane.com/kb/gridpane-default-cache-exclusions/
- Working with WooCommerce — https://gridpane.com/kb/working-with-woocommerce/
