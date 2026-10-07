---
name: gridpane-nginx-config
description: >-
  Use when adding or reviewing custom Nginx (or OpenLiteSpeed) configuration on a
  GridPane server: blocking xmlrpc.php, rate-limiting wp-login.php, custom
  headers, redirects, upload/body size, bypassing the cache for a path, or
  allow/deny by IP. Covers the supported include locations that GridPane will not
  overwrite, the edit-backup-validate-reload workflow, ready-to-use snippets and
  their rollbacks. Do not use for Nginx on non-GridPane servers, or for PHP/MySQL
  tuning (use gridpane-server-diagnostics).
---

# gridpane-nginx-config

Add custom web-server configuration the supported way on GridPane, so it survives
GridPane regenerating the site's managed config. Prefer a `gp` command where one
exists (e.g. block xmlrpc via `gp site … -disable-xmlrpc`); use custom includes
when there is no command.

Load `gridpane-core` first. Snippets and their rollbacks: `references/snippets.md`.

## Prerequisites

- Root (or sudo) over SSH.
- `gridpane-core` loaded.
- Confirm the web server: **Nginx** or **OpenLiteSpeed**. This skill's Nginx
  steps do not apply to OLS.
- The exact site URL and whether the change is **one site** or **all sites**.

## Workflow

1. **Identify the stack.**
   ```bash
   # [READ] Which web server is running?
   gp ngx -status || gpols -status
   ```
2. **Choose the correct include.** Never edit the managed vhost
   (`/etc/nginx/sites-available/{site.url}`) or `common` files: GridPane
   regenerates them. Put rules in:
   - one site: `/var/www/{site.url}/nginx/myrule-main-context.conf`
   - all sites: `/etc/nginx/extra.d/myrule-main-context.conf`
   - http context (e.g. `limit_req_zone`): `/etc/nginx/extra.d/http-context.conf`
   - then copy server-wide files into `/etc/nginx/extra.d/_custom/` so GridPane
     does not overwrite them.
3. **Back up** any existing file before changing it.
   ```bash
   # [READ] Timestamped copy, also your rollback artefact.
   cp -a /etc/nginx/extra.d/myrule-main-context.conf \
         /etc/nginx/extra.d/myrule-main-context.conf.bak-$(date +%Y%m%d%H%M%S)
   ```
4. **Write the rule.**
5. **Validate.**
   ```bash
   # [READ] Nginx syntax test. A failure means do NOT reload.
   nginx -t
   ```
6. **Reload.**
   ```bash
   # [WRITE] Reload Nginx to apply. Blast radius depends on the include location.
   # Rollback: restore the .bak copy, `nginx -t`, reload again.
   # Confirm before running.
   gp ngx -reload
   ```
7. **Verify** with a request.

## Verify

```bash
# [READ] Confirm the rule behaves as intended (run from the server).
curl -sSI https://example.com/xmlrpc.php | head -n 5
```

Check the status code and headers match what you intended (e.g. 403 for a block,
the new header present, the redirect Location correct).

## Rollback

For every snippet: restore the `.bak-<timestamp>` copy (or delete the file you
created if it is new), run `nginx -t`, then `gp ngx -reload`. Never leave a
failed config reloaded; a broken Nginx config takes down every site on the box.

## Gotchas

- **Managed files are overwritten.** Rules in `sites-available/{site.url}` or
  `/etc/nginx/common/` disappear on the next `gp`/panel change. Use includes.
- **Duplicate `location` blocks are a hard error.** If your rule matches a path
  GridPane already has a `location` for, `nginx -t` fails. Prefer the `gp`
  command, or a more specific match, rather than shadowing GridPane's block.
- **Server-wide includes have server-wide blast radius.** A syntax error in
  `/etc/nginx/extra.d/` affects **every site**. Always run `nginx -t`.
- **OpenLiteSpeed differs.** OLS has no Nginx-style includes; it uses its own
  config (e.g. `/usr/local/lsws/conf/ip_deny.conf`) and `gpols httpd`. See
  `references/snippets.md` for the OLS notes and `gridpane-security` for OLS IP
  blocking.
- **Cache can mask the change.** A custom header or redirect may be served from
  cache. Clear the site cache ([WRITE]) before concluding the rule is wrong.

## Sources

- Adding Custom Nginx Rules for Plugins — https://gridpane.com/kb/adding-custom-nginx-rules-for-plugins-a-general-guide/
- Configure Nginx — https://gridpane.com/kb/configure-nginx/
- Additional Security Measure: Nginx Includes — https://gridpane.com/kb/additional-security-measure-nginx-includes/
- Useful Commands (ban IPs with Nginx rules) — https://gridpane.com/kb/useful-commands-for-managing-gridpane-servers/

Last verified: 2026-10-07
