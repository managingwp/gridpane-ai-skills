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

There is no single "which is on" `gp` command. Determine it from the site
customizer's Caching tab, from the response headers (below), or from the server's
config. Do not guess and reconfigure blindly — changing the page cache method
requires resetting the TTL manually when switching from Redis to FastCGI.

The two page caches emit **different response headers**. Check both before
concluding anything:

| Page cache | Success header | TTL header | Bypass-reason header |
|---|---|---|---|
| Redis page cache | `X-Grid-SRCache-Fetch: HIT \| MISS \| BYPASS` | `X-Grid-SRCache-TTL` | `x-grid-srcache-skip` |
| FastCGI page cache | `X-Grid-Cache: HIT \| MISS \| BYPASS \| STALE` | `X-Grid-Cache-TTL` | `x-grid-cache-skip` |

**Trap:** the absence of `X-Grid-Cache` does **not** mean the site is uncached.
A Redis-page-cached site emits `X-Grid-SRCache-Fetch` instead. If you only look
for `X-Grid-Cache`, you will wrongly report a Redis-cached site as uncached.

### Server-side: confirm the method per site

The response header is one source; the site's own Nginx config is the other. Use
both and check that they agree. These are GridPane-managed filenames:

| Page cache | Per-site config file(s) |
|---|---|
| FastCGI | `/etc/nginx/common/{site.url}-fcgi-cache-var.conf` |
| Redis (SRCache) | `/etc/nginx/common/{site.url}-wp-redis.conf`, `/etc/nginx/common/{site.url}-proxy-http-rediscache.conf`, `/etc/nginx/common/{site.url}-proxy-https-rediscache.conf` |
| ModSec reverse-proxy cache (only when ModSecurity is enabled) | `/etc/nginx/common/{site.url}-proxy-cache-var.conf` |

```bash
# [READ] Which page-cache config files exist for this site.
ls -1 /etc/nginx/common/{site.url}-fcgi-cache-var.conf \
      /etc/nginx/common/{site.url}-wp-redis.conf \
      /etc/nginx/common/{site.url}-proxy-http-rediscache.conf \
      /etc/nginx/common/{site.url}-proxy-https-rediscache.conf 2>/dev/null
```

```bash
# [READ] Which page-cache directives the site's Nginx config actually sets.
# srcache_*/redis2_query => Redis page cache; fastcgi_cache => FastCGI.
grep -RhoE 'srcache[a-z_]*|redis2_query' /etc/nginx/sites-available/{site.url} /etc/nginx/common/{site.url}-*.conf 2>/dev/null | sort -u
grep -RhoE 'fastcgi_cache[a-z_]*'         /etc/nginx/sites-available/{site.url} /etc/nginx/common/{site.url}-*.conf 2>/dev/null | sort -u
```

The directives are authoritative: if the config sets `srcache_*`/`redis2_query`
the site uses Redis page cache; if it sets `fastcgi_cache` it uses FastCGI. Then
confirm with the live header — a Redis-cached site answers with
`X-Grid-SRCache-Fetch`, a FastCGI site with `X-Grid-Cache`.

### The definitive per-site check: `cache-type`

The site's `logs/{site.url}.env` file records the page cache method directly:

```bash
# [READ] The site's recorded cache method and object-cache state.
grep -E '^(cache-type|redis-object-cache|ngx-redis-cache-valid|nginx-caching-ttl):' \
  /var/www/{site.url}/logs/{site.url}.env
```

- `cache-type:redis` → Redis page cache → expect `X-Grid-SRCache-Fetch`.
- A FastCGI/off value has not been observed yet; confirm the exact string on a
  real server before relying on it (see `OPEN-QUESTIONS.md`).

Other per-site signals that should agree:

```bash
# [READ] Per-site cache skip includes (Redis vs FastCGI).
ls -1 /var/www/{site.url}/nginx/*-skip-redis-cache-context.conf \
      /var/www/{site.url}/nginx/*-skip-fcgi-cache-context.conf 2>/dev/null
```

Full key reference: `gridpane-core/references/site-env.md`. **If the recorded
method, the config directives and the response header disagree, do not guess:**
the site may be mid-switch, or the request may be bypassed. Read the skip header
(`x-grid-srcache-skip` / `x-grid-cache-skip`) before drawing a conclusion.

### Server-side: the server-wide layer (`/root/gridenv`)

`/root/gridenv/nginx.env` records the server-wide Nginx cache configuration, and
`redis-page.env` / `redis-object.env` show which Redis services exist. This layer
proves the cache machinery is present and how it is tuned, but **not** that a
given site uses it.

```bash
# [READ] Server-wide Nginx cache config (these keys are not secrets).
grep -E '^(fastcgi|proxy)_(cache|buffering)' /root/gridenv/nginx.env
```

```bash
# [READ] Which Redis services this server runs (split layout).
ls -1 /root/gridenv/redis-page.env /root/gridenv/redis-object.env 2>/dev/null
```

What the `nginx.env` cache keys mean:

- `fastcgi_cache_size` / `proxy_cache_size` — max cache zone size in MB. These
  define the server-wide cache zones; **do not read them as "this site uses
  FastCGI"**. A Redis-page-cached site on the same server still has them.
- `fastcgi_cache_background_update`, `fastcgi_cache_revalidate`,
  `proxy_cache_background_update`, `proxy_cache_revalidate` — cache refresh
  behaviour (both default `on`).
- `fastcgi_buffering`, `proxy_buffering` — response buffering, not the cache
  itself.

The stronger server-wide signals for Redis page/object caching are the
`promethean.env` flags (`redis-page:true`, `redis-object:true`) and the split
Redis services in `monit.env` — not the mere presence of `redis.env`, which can
coexist with the split files (observed on a real capture, 2026-10-09).

The per-site Nginx config and the live headers are authoritative for a single
site; `/root/gridenv` only sets the server-wide context. See
`gridpane-core/references/gridenv.md`.

## Verify hits (response headers)

Load the site **in an incognito window** (logged-in sessions bypass cache) and
inspect the response headers. Look for **either** cache family — Redis page cache
and FastCGI are mutually exclusive per site:

- `X-Grid-SRCache-Fetch: HIT | MISS | BYPASS` (Redis page cache)
  - `HIT` — served from cache.
  - `MISS` — not cached yet; reload should give `HIT`.
  - `BYPASS` — this page is excluded and will never be cached. Read
    `x-grid-srcache-skip` for the reason.
- `X-Grid-Cache: HIT | MISS | BYPASS | STALE` (FastCGI)
  - as above, plus `STALE` — the browser's copy expired; still served from the
    server cache and refreshed in the background.
  - `x-grid-cache-skip` gives the bypass reason.
- `X-Grid-SRCache-TTL` / `X-Grid-Cache-TTL: <seconds>` — the cache TTL.

```bash
# [READ] Check both cache header families (use a cache-busting UA if needed).
curl -sSI https://example.com | grep -iE 'x-grid-(cache|srcache)'
```

If **neither** family is present, page caching is off for that request. Before
concluding "caching is off", confirm you are logged out, in a fresh incognito
window, and hitting an HTML page (not an asset, REST or admin URL).

FastCGI uses **microcaching**: default TTL is **1 second**. Getting `HIT` with
FastCGI is hard because of that; `STALE` still means the server cache is working.
Redis page caching defaults to a much longer TTL (2592000 seconds = 30 days) and
suits mostly-static content; FastCGI suits high-concurrency or frequently-changing
content.

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

1. **You checked the wrong header.** Redis page caching emits
   `X-Grid-SRCache-Fetch`, not `X-Grid-Cache`. A missing `X-Grid-Cache` is not
   proof the site is uncached — check both families first.
2. **You are logged in.** Logged-in requests set `cache-control: private,
   no-store` and are never cached. Test in incognito.
3. **The page is excluded.** Check GridPane's default cache exclusions and any
   per-page exclusions.
4. **`BYPASS` in the header.** The path or a cookie/query string triggered an
   exclusion. Read `x-grid-srcache-skip` (Redis) or `x-grid-cache-skip` (FastCGI)
   for the exact reason.
5. **WooCommerce / dynamic pages.** Cart, checkout and account pages legitimately
   bypass cache. See the WooCommerce KB article.
6. **Query strings.** Some query strings force an uncached response; there is a
   KB article on removing specific query strings so the cached version loads.
7. **FastCGI TTL is 1 second.** You will often see `STALE`, not `HIT`; that is
   expected and healthy.
8. **OPcache still holds old PHP.** `opcache.revalidate_freq` (in
   `/root/gridenv/php{VERSION}.env`) delays PHP file changes; that is separate
   from page caching.
9. **A CDN in front.** Cloudflare may serve its own cached copy; check Cloudflare
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
- Diagnosing Caching Issues (both header families) — https://gridpane.com/kb/diagnosing-caching-issues/
- Exclude a Page or Cookie from Nginx Server Caching (skip configs) — https://gridpane.com/kb/exclude-a-page-from-server-caching/
- Configure Nginx (Redis cache config filenames) — https://gridpane.com/kb/configure-nginx/
- Clear all caches (all methods) — https://gridpane.com/kb/how-to-clear-your-website-caches-all-methods/
- Default cache exclusions — https://gridpane.com/kb/gridpane-default-cache-exclusions/
- Working with WooCommerce — https://gridpane.com/kb/working-with-woocommerce/

Last verified: 2026-10-09
