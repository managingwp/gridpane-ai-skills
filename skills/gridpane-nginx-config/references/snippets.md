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
    include /etc/nginx/common/*-php-context.conf;
}
```

- Rollout: add the zone to `http-context.conf`, the location to the site include,
  `nginx -t`, reload.
- Rollback: remove both blocks, `nginx -t`, reload.
- Note: if the location conflicts with GridPane's existing wp-login handling,
  `nginx -t` fails; use GridPane's documented PHP-context include instead. The
  exact PHP-include filename should be confirmed on the server (see Unverified).

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

## OpenLiteSpeed notes

OLS does not use these Nginx includes. Related OLS mechanisms:

- IP deny list: `/usr/local/lsws/conf/ip_deny.conf`, then `gpols httpd`.
- OLS server-level redirects and custom headers have their own KB pages.
- Caching on OLS is LSCache / the LiteSpeed Cache plugin, not FastCGI cache.

## Unverified

- The exact GridPane PHP-context include filename used inside the PHP `location`
  (the KB references a `*-php-context.conf` include for PHP-level rules). Confirm
  on the server before relying on the rate-limit `include` line above.
- Whether the default GridPane wp-login handling uses an exact-match `location`
  that would collide with the snippet above.

## Sources

- Adding Custom Nginx Rules for Plugins — https://gridpane.com/kb/adding-custom-nginx-rules-for-plugins-a-general-guide/
- How to Set Up Custom Rate Limiting in Nginx — https://gridpane.com/kb/how-to-set-up-custom-rate-limiting-in-nginx/
- Additional Security Measure: Nginx Includes — https://gridpane.com/kb/additional-security-measure-nginx-includes/
- GridPane Default Cache Exclusions — https://gridpane.com/kb/gridpane-default-cache-exclusions/
- Allow or Deny IP Addresses on OpenLiteSpeed — https://gridpane.com/kb/allow-or-deny-ip-addresses-on-openlitespeed/
