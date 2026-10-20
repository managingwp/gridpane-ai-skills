# Nginx snippets

Vetted, standard Nginx snippets placed in GridPane's supported include locations.
Each has a rollout and a rollback. All are [WRITE] because they change server
behaviour.

File targets (see `gridpane-core/references/paths.md`):

- one site: `/var/www/{site.url}/nginx/{name}-main-context.conf`
- all sites: `/etc/nginx/extra.d/{name}-main-context.conf` (then copy to
  `/etc/nginx/extra.d/_custom/`)
- http context: `/etc/nginx/extra.d/http-context.conf`

**Always** `nginx -t` then `gp ngx -reload`.

---

## Prefer the `gp` command where one exists

| Goal | Prefer this command over a snippet |
|---|---|
| Block `xmlrpc.php` | `gp site {site.url} -disable-xmlrpc` |
| Block `wp-content.php` | `gp site {site.url} -block-wp-content.php` |
| Max request body size | `gp stack nginx limits -site-max-body-size {value} {site.url}` |
| Custom response headers (security set) | `gp site {site.url} -csp-header-on` for CSP |

Use a snippet only when GridPane has no command for it.

---

## Block xmlrpc.php by hand (if not using the gp command)

Add to a site include. If Nginx reports a duplicate `location`, use the `gp`
command instead.

```nginx
location = /xmlrpc.php {
    deny all;
    return 403;
}
```

- Rollout: create the file, `nginx -t`, `gp ngx -reload`.
- Rollback: `gp site {site.url} -enable-xmlrpc` or delete the include, then
  `nginx -t` and reload.

## Rate-limit wp-login.php

Define the zone once at http context:

```nginx
limit_req_zone $binary_remote_addr zone=wplogin:10m rate=5r/m;
```

Then apply it in a site include:

```nginx
location = /wp-login.php {
    limit_req zone=wplogin burst=5 nodelay;
    # let GridPane's own php handling serve the request:
    include /etc/nginx/extra.d/*php-context.conf;
    include /etc/nginx/extra.d/*-php-context.conf;
}
```

- Rollout: add the zone to `http-context.conf`, the location to the site include,
  `nginx -t`, reload.
- Rollback: remove both blocks, `nginx -t`, reload.
- Note: GridPane's PHP `location` includes
  `/etc/nginx/extra.d/*php-context.conf` and `*-php-context.conf`
  (`lib/stack.sh:4106-4107`); include the same files so PHP still runs. If the
  location conflicts with GridPane's existing wp-login handling, `nginx -t`
  fails; use a different path or the documented PHP-context include instead.

## Add a custom response header

```nginx
add_header X-Example "gridpane" always;
```

- Rollout: site include, `nginx -t`, reload.
- Rollback: remove the line, `nginx -t`, reload.
- Note: `add_header` in a nested block overrides the outer set, so check for an
  existing `add_header` before adding.

## Redirect a path or domain

```nginx
return 301 https://example.com/new-location;
```

- Rollout: site include, `nginx -t`, reload.
- Rollback: remove the include, `nginx -t`, reload.
- Note: for domain-level routing (www vs root) prefer
  `gp site {site.url} -route-domain-www|root|off`.

## Allow only specific IPs

```nginx
allow 203.0.113.10;
allow 198.51.100.0/24;
deny all;
```

- Rollout: in the relevant site include (or a `location`), `nginx -t`, reload.
- Rollback: remove the block, `nginx -t`, reload. **Do not lock yourself out of
  wp-admin or the whole site without also allowing your own IP.**

## Block specific IPs server-wide

Add denies to the http-context include, then protect it from regeneration:

```nginx
deny 203.0.113.10;
deny 198.51.100.11;
```

- Rollout: edit `/etc/nginx/extra.d/http-context.conf`, copy to
  `/etc/nginx/extra.d/_custom/http-context.conf`, `nginx -t`, reload.
- Rollback: remove the lines from both copies, `nginx -t`, reload.

## Bypass / exclude a page from server caching

Do **not** invent Nginx cache variables. Use the supported mechanisms:

- GridPane default cache exclusions and per-page exclusions (Nginx Helper), or
- the PHP-header exclusion method.

See `gridpane-wordpress/references/caching.md` and the KB links in Sources.

---

## OpenLiteSpeed (OLS) snippets

OLS has no Nginx-style includes. Per-site custom config lives in
`/var/www/{site.url}/ols/` and is compiled into
`/usr/local/lsws/conf/vhosts/{site.url}/vhconf.conf` by
`gpols site {site.url}`. Server-wide files live under `/usr/local/lsws/conf/`.

Workflow for every OLS snippet: back up the file, edit it, run `gpols test`,
then `gpols site {site.url}` (per site) or `gpols httpd` (server-wide). Rollback:
restore the backup and re-run the same command.

`gp site {site.url} -disable-xmlrpc` works on both stacks; prefer it to a
hand-written rewrite.

### Custom headers (per site)

File: `/var/www/{site.url}/ols/headers.conf`. One `Name value` per line. There is
no server-wide custom-header file on OLS — each site must be edited.

```nginx
X-Example-Header gridpane
Referrer-Policy strict-origin-when-cross-origin
```

Rollout: edit the file, `gpols test`, `gpols site {site.url}`. Rollback: restore
the `.bak` copy and re-run. Verify with
`curl -sSI https://example.com | grep -i x-example-header`.

### Redirects (per site)

File: `/var/www/{site.url}/ols/rewrites.conf`. `RewriteEngine On` is not needed;
one rule per line.

```apache
RewriteRule ^/?old-page$ new-page [L,R=301]
RewriteRule ^/?old-page/(.*)$ new-page/$1 [L,R=301]
RewriteCond %{HTTP_HOST} ^old\.example [NC]
RewriteRule ^(.*)$ https://new.example/$1 [L,R=301,NC]
```

Rollout: edit, `gpols test`, `gpols site {site.url}`. Rollback: restore the
backup and re-run. Verify with `curl -sSI`.

### IP allow / deny

Server-wide: `/usr/local/lsws/conf/ip_allow.conf`, `ip_deny.conf`.
Per site: `/var/www/{site.url}/ols/ip_allow.conf`, `ip_deny.conf`.
One IP or subnet per line. Server-level deny closes the connection; site-level
deny returns 403. Site rules do not override server rules.

Rollout: edit, `gpols test`, then `gpols httpd` (server) or
`gpols site {site.url}` (site). Rollback: restore the backup and re-run. Verify
from an allowed and a denied address.

### Not available on OLS

- **Nginx `limit_req` / `limit_req_zone` rate limiting** has no direct OLS
  equivalent; use the 7G WAF, Fail2ban, or OLS anti-DDoS controls instead.
- **Nginx cache-bypass includes** (`*-skip-*-cache-context.conf`) do not apply;
  exclude pages in the LSCache plugin (`gridpane-wordpress/references/caching.md`).
- **Server-wide custom headers** are not supported on OLS; edit each site's
  `headers.conf`.
- **`location` blocks / `include *-main-context.conf`** are Nginx-only.

## Unverified

- Whether the default GridPane wp-login handling uses an exact-match `location`
  that would collide with the snippet above.
- OLS rate limiting: whether a supported rewrite/access-control pattern exists
  (no documented `limit_req` equivalent).

## Sources

- Adding Custom Nginx Rules for Plugins — https://gridpane.com/kb/adding-custom-nginx-rules-for-plugins-a-general-guide/
- How to Set Up Custom Rate Limiting in Nginx — https://gridpane.com/kb/how-to-set-up-custom-rate-limiting-in-nginx/
- Additional Security Measure: Nginx Includes — https://gridpane.com/kb/additional-security-measure-nginx-includes/
- GridPane Default Cache Exclusions — https://gridpane.com/kb/gridpane-default-cache-exclusions/
- Allow or Deny IP Addresses on OpenLiteSpeed — https://gridpane.com/kb/allow-or-deny-ip-addresses-on-openlitespeed/
- How to Add Your Own Custom Headers on OpenLiteSpeed — https://gridpane.com/kb/how-to-add-your-own-custom-headers-on-openlitespeed/
- How to Create Server-Level Redirects on OpenLiteSpeed (OLS) — https://gridpane.com/kb/how-to-create-server-level-redirects-on-openlitespeed-ols/
