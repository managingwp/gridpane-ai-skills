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
- Confirm the web server: **Nginx** or **OpenLiteSpeed**. The workflow is
  separate (Nginx includes vs the OLS `ols/` files); use the section for your
  stack.
- The exact site URL and whether the change is **one site** or **all sites**.

## Workflow

1. **Identify the stack.**
   ```bash
   # [READ] Which web server is running?
   gp ngx -status 2>/dev/null || systemctl is-active lshttpd
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

## OpenLiteSpeed workflow

OLS has no Nginx-style includes. Custom config lives in the site's `ols/`
directory (or `/usr/local/lsws/conf/` for server-wide files) and is compiled into
`vhconf.conf`/`httpd_config.conf` by `gpols`.

1. **Identify the stack.** `systemctl is-active lshttpd` returns `active` on OLS
   (and `gp ngx -status` does not).
2. **Choose the supported file:**
   - per-site headers: `/var/www/{site.url}/ols/headers.conf`
   - per-site rewrites: `/var/www/{site.url}/ols/rewrites.conf`
   - per-site IP allow/deny: `/var/www/{site.url}/ols/ip_allow.conf`,
     `ip_deny.conf`
   - server-wide IP allow/deny: `/usr/local/lsws/conf/ip_allow.conf`,
     `ip_deny.conf`

   Never edit `vhconf.conf` or `httpd_config.conf`; they are generated.
3. **Back up** the file you will edit (timestamped copy).
4. **Edit** the file (one rule/header/IP per line).
5. **Validate.**

   ```bash
   # [READ] OLS config test. A failure means do NOT regenerate/restart.
   gpols test
   ```
6. **Regenerate and restart.**

   ```bash
   # [WRITE] Compile the site's ols/ files into its vhconf and restart OLS.
   # Blast radius: one site. Rollback: restore the .bak copy and re-run.
   # Confirm before running.
   gpols site example.com
   ```

   ```bash
   # [WRITE] Server-wide: regenerate httpd_config.conf and restart OLS.
   # Blast radius: every site on the server. Confirm before running.
   gpols httpd
   ```
7. **Verify** with `curl -sSI` (header/redirect), or from an allowed/denied IP.

Server-wide vs per-site: `gpols httpd` affects every site; `gpols site` affects
one. OLS site-level allow/deny does not override server-level rules.

## Verify

```bash
# [READ] Confirm the rule behaves as intended (run from the server).
curl -sSI https://example.com/xmlrpc.php | head -n 5
```

Check the status code and headers match what you intended (e.g. 403 for a block,
the new header present, the redirect Location correct).

## Rollback

For every snippet: restore the `.bak-<timestamp>` copy (or delete the file you
created if it is new), then re-validate and reload.

- **Nginx:** run `nginx -t`, then `gp ngx -reload`.
- **OLS:** run `gpols test`, then `gpols site {site.url}` (per site) or
  `gpols httpd` (server-wide).

Never leave a failed config loaded; a broken Nginx config or `httpd_config.conf`
takes down every site on the box.

## Gotchas

- **Managed files are overwritten.** Rules in `sites-available/{site.url}` or
  `/etc/nginx/common/` disappear on the next `gp`/panel change. Use includes.
- **Duplicate `location` blocks are a hard error.** If your rule matches a path
  GridPane already has a `location` for, `nginx -t` fails. Prefer the `gp`
  command, or a more specific match, rather than shadowing GridPane's block.
- **Server-wide includes have server-wide blast radius.** A syntax error in
  `/etc/nginx/extra.d/` affects **every site**. Always run `nginx -t`.
- **OpenLiteSpeed differs.** No Nginx includes: per-site files live in
  `/var/www/{site.url}/ols/` (`headers.conf`, `rewrites.conf`, `ip_allow.conf`,
  `ip_deny.conf`), server-wide IP files in `/usr/local/lsws/conf/`, and `gpols
  site` / `gpols httpd` regenerate and restart. There is no server-wide custom
  header and no `limit_req` equivalent. See `references/snippets.md`.
- **Cache can mask the change.** A custom header or redirect may be served from
  cache. Clear the site cache ([WRITE]) before concluding the rule is wrong.

## Sources

- Adding Custom Nginx Rules for Plugins — https://gridpane.com/kb/adding-custom-nginx-rules-for-plugins-a-general-guide/
- Configure Nginx — https://gridpane.com/kb/configure-nginx/
- Additional Security Measure: Nginx Includes — https://gridpane.com/kb/additional-security-measure-nginx-includes/
- Useful Commands (ban IPs with Nginx rules) — https://gridpane.com/kb/useful-commands-for-managing-gridpane-servers/
- How to Add Your Own Custom Headers on OpenLiteSpeed — https://gridpane.com/kb/how-to-add-your-own-custom-headers-on-openlitespeed/
- How to Create Server-Level Redirects on OpenLiteSpeed (OLS) — https://gridpane.com/kb/how-to-create-server-level-redirects-on-openlitespeed-ols/
- Allow or Deny IP Addresses on OpenLiteSpeed — https://gridpane.com/kb/allow-or-deny-ip-addresses-on-openlitespeed/

Last verified: 2026-10-19
