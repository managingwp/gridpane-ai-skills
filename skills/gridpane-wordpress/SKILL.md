---
name: gridpane-wordpress
description: >-
  Use for WordPress-level work on a GridPane server: running WP-CLI as the correct
  site system user via the gp wp wrapper, checking and purging caching (Nginx
  FastCGI page cache, Redis page cache, Redis object cache), diagnosing "cache
  isn't working", WP-Cron vs GP-Cron, staging push/pull, site migrations, and
  enabling WP_DEBUG safely. For suspected compromise hand off to gridpane-security;
  for a site that is down start with gridpane-incident-triage.
---

# gridpane-wordpress

WordPress operations on GridPane. The recurring theme: run commands as the right
system user, and understand the layered cache before deciding a change "didn't
work".

Load `gridpane-core` first. Caching detail is in `references/caching.md`.

## Prerequisites

- `gridpane-core` loaded.
- For WP-CLI, prefer the wrapper so commands run as the site's own system user.
- Root (or sudo) over SSH for server-side cache/service actions.

## Workflow

1. **Establish the site and its user.** Do not run WP-CLI as root against site
   files.
2. **Know the cache layers** before diagnosing "it didn't change": page cache,
   object cache, and any CDN/Cloudflare.
3. **Use `gp wp` for WordPress commands.**
4. **Diagnose before changing**; every cache purge or service action is [WRITE].

Run WP-CLI correctly:

```bash
# [READ] WP-CLI as the site system user (no --allow-root, no path juggling).
gp wp example.com plugin list
```

```bash
# [READ] Raw WP-CLI as the site user, if you need a flag `gp wp` cannot pass
# (for example --ssh). Run from the webroot.
sudo -u exampleuser wp plugin list --path=/var/www/example.com/htdocs
```

## Commands

Cache (details and causes in `references/caching.md`):

```bash
# [WRITE] Clear every cache for one site (page, object, opcache).
# Blast radius: site example.com only. Rollback: caches rebuild on next visit.
# Confirm before running.
gp fix cached example.com
```

```bash
# [WRITE] Enable the Nginx FastCGI page cache with a TTL (seconds).
gp site example.com -fastcgi-cache -ttl 1
```

```bash
# [WRITE] Toggle Redis object caching for one site.
gp site example.com -redis-object-caching on
```

Cron, debug, database:

```bash
# [READ] Show scheduled events (before changing cron behaviour).
gp wp example.com cron event list
```

```bash
# [WRITE] Turn secure WP debug on for one site (and off when finished).
gp site example.com -wp-debug-on
gp site example.com -wp-debug-off
```

```bash
# [READ] Safe plugin bisect: load WP with no plugins to see if the site's fatal
# error disappears.
gp wp example.com plugin list --skip-plugins
```

## Verify

- Cache: response header `X-Grid-Cache` (`HIT`/`MISS`/`BYPASS`/`STALE`) and
  `X-Grid-Cache-TTL`.
- Cron: `gp wp {site.url} cron event list`, or the GP-Cron file in
  `/etc/cron.d/gp-cron-{site-with-dashes}`.
- Debug: read `/var/www/{site.url}/logs/debug.log`, then switch debug back off.

## Rollback

- Cache enable → `gp site {site.url} -cache-off`, or toggle object cache off.
- Debug on → `-wp-debug-off` (do not leave it on).
- Staging push → no automated rollback; see staging below.

## Staging, cron and migrations

### WP-Cron vs GP-Cron

- **GP-Cron** triggers WordPress cron at the server level and disables native
  WP-Cron via `wp-config.php`. Active by **default** on Ubuntu 22.04+ (5-minute
  interval, "fuzziness" 270s); **not** active by default on Ubuntu 20.04.
- Set or change it per site:

  ```bash
  # [WRITE] Every 15 minutes (default fuzziness). Blast radius: one site.
  gp site example.com -gpcron-on 15
  ```

  ```bash
  # [WRITE] Disable GP-Cron for a site.
  gp site example.com -gpcron-off
  ```

- Cron files live in `/etc/cron.d/gp-cron-{site.url-with-dashes}`.
- List sites using GP-Cron:
  ```bash
  # [READ] Sites with cron:true in their env file.
  grep 'cron:true' /var/www/*/logs/*.env
  ```
- **Duplicate-cron risk on multi-server / load-balanced setups:** if every app
  server runs GP-Cron for the same site, scheduled tasks fire multiple times.
  Ensure only one server runs cron for a given site, or use a shared lock.

### Staging

- Push **Live → Staging** to test; push **Staging → Live** to deploy.
- **Staging → Live overwrites production files and database.** Treat it as
  [DESTRUCTIVE]: require the user to name the action, confirm twice and verify a
  backup exists first.
- Failures are logged in `/var/www/{site.url}/logs/staging.log`.

  ```bash
  # [READ] Why did the last staging push fail?
  tail -n 50 /var/www/example.com/logs/staging.log
  ```

### Migrations checklist

Not a script; work items:

1. **DNS** — records point at the target before SSL provisioning.
2. **SSL** — provision after DNS resolves; failure reasons in
   `/var/www/{site.url}/logs/ssl-provision.log`.
3. **Search-replace** — rewrite the old domain to the new one across the DB:
   ```bash
   # [WRITE] Rewrite URLs (dry run first). Blast radius: this site's database.
   # Backup the database first. Confirm before running.
   gp wp example.com search-replace old.example new.example \
     --dry-run --precise --all-tables --skip-columns=guid --report-changed-only
   ```
4. **Cache** — purge all caches after the change ([WRITE]).
5. **Cron** — confirm GP-Cron/WP-Cron is correct for the new host.
6. **Email** — ensure SMTP/transactional email still works.

Note the GridPane `wp-config.php` sits one level above `htdocs` and holds
GridPane-specific config; when migrating, remove any second `wp-config.php` in
`htdocs` and keep GridPane's. Custom PHP constants go in the user-configs file.
See `gridpane-core/references/paths.md`.

## Gotchas

- **Never run WP-CLI as root against site files** — it can reset ownership and
  permissions. Use `gp wp` or `sudo -u {siteuser}`.
- **`--ssh` is unsupported through `gp wp`**; use raw WP-CLI for that flag.
- **Logged-in users never get a cached page** (`cache-control: private,
  no-store`). A "missing" cache while logged in is expected.
- **Debug on is a liability.** Turn `-wp-debug-off` as soon as you are done.
- **Suspected compromise** (unexpected admins, spam, redirects, strange files):
  stop and hand off to `gridpane-security`.

## Sources

- GP WP-CLI — https://gridpane.com/kb/gp-wp-cli/
- WP-Cron and GP-Cron — https://gridpane.com/kb/wp-cron-and-gridpanes-gp-cron-updated/
- FastCGI Page Caching — https://gridpane.com/kb/using-gridpane-nginx-fastcgi-page-caching/
- Redis Object Caching — https://gridpane.com/kb/using-gridpane-redis-object-caching/
- WP Debug and Query Monitor — https://gridpane.com/kb/wordpress-debug-and-query-monitor/
- Migrations, Cloning and wp-config.php — https://gridpane.com/kb/migrations-cloning-and-the-wordpress-configuration-file-wp-config-php/

Last verified: 2026-10-07
