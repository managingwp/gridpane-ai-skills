# WAFs: 6G, 7G and ModSecurity

GridPane ships the 6G and 7G web application firewalls and ModSecurity support.
7G is the newer, recommended ruleset. All are per site.

## What 7G covers

7G parses requests against rulesets for **bad bots, bad methods, bad query
strings, bad referrers and bad requests**, protecting against directory
traversal, XSS, cache poisoning, SQL/PHP/code injection, file injection,
WordPress-specific exploits, webshells and PHP information leakage.

## Enable / disable

Per site, via the control panel's security tab or `gp` ([WRITE]):

| Label | Command |
|---|---|
| [WRITE] | `gp site {site.url} -7g-on` / `-7g-off` |
| [WRITE] | `gp site {site.url} -6g-on` / `-6g-off` |
| [WRITE] | `gp site {site.url} -modsec-on` / `-modsec-off` |
| [WRITE] | `gp site {site.url} -modsec -paranoia-level {1-4}` |
| [WRITE] | `gp site {site.url} -modsec -anomaly-threshold {int}` |

Enabling 7G turns on all rulesets; then toggle individual ones:

| Label | Command |
|---|---|
| [WRITE] | `gp site {site.url} 7g -bad-bots on` / `off` |
| [WRITE] | `gp site {site.url} 7g -bad-query-string on` / `off` |
| [WRITE] | `gp site {site.url} 7g -bad-referer on` / `off` |
| [WRITE] | `gp site {site.url} 7g -bad-request on` / `off` |
| [WRITE] | `gp site {site.url} 7g -bad-methods on` / `off` |

## Reading what was blocked

```bash
# [READ] 7G block events for a site (ruleset and rule number are included).
tail -n 50 /var/www/example.com/logs/7g.log
```

```bash
# [READ] 6G log.
tail -n 50 /var/www/example.com/logs/6g.log
```

```bash
# [READ] ModSecurity logs to the site error log on Nginx.
grep -i modsecurity /var/log/nginx/example.com.error.log | tail -n 30
```

A 7G log line names the ruleset and numbered rule, e.g. `:not_allowed_method_6:`
or `:bad_querystring_12:`. Use that to craft a precise whitelist.

Config files (all managed except the whitelist includes):

- Ruleset maps: `/etc/nginx/common/7g-mappings.conf`
- Per-site 7G config: `/etc/nginx/common/{site.url}-7g.conf`
- Whitelist includes (safe to add):
  - server-wide: `/etc/nginx/extra.d/*7g-context.conf`
  - per site: `/var/www/{site.url}/nginx/*-7g-context.conf`

## Whitelisting a false positive

7G flips a variable from `0` to `1` when a rule is breached; setting it back to
`0` in an include lets the request through:

- `$7g_drop_bad_bot`
- `$7g_drop_bad_referer`
- `$7g_drop_bad_query_string`
- `$7g_drop_bad_request`
- `$7g_drop_bad_method`

**Example: whitelist one IP against every rule** (site include):

```nginx
if ($remote_addr = "203.0.113.10") {
    set $7g_drop_bad_request 0;
    set $7g_drop_bad_referer 0;
    set $7g_drop_bad_query_string 0;
    set $7g_drop_bad_method 0;
    set $7g_drop_bad_bot 0;
}
```

**Example: allow one specific rule (rule 6 of bad methods) for one IP:**

```nginx
set $exclusion_rule_match "";
if ($remote_addr = "203.0.113.10") {
    set $exclusion_rule_match 6;
}
if ($not_allowed_method_7g = $exclusion_rule_match) {
    set $7g_drop_bad_method 0;
}
```

**Example: whitelist a plugin URI against a bad-request rule:**

```nginx
set $exclusion_rule_match "";
if ($uri ~ ^/wp-content/plugins/some-plugin/) {
    set $exclusion_rule_match 7;
}
if ($bad_request_7g = $exclusion_rule_match) {
    set $7g_drop_bad_request 0;
}
```

Rollout and rollback for any whitelist:

```bash
# [WRITE] Create the include, then validate and reload.
# Blast radius: the site (or server if placed in /etc/nginx/extra.d/).
# Backup: none needed for a new file; if editing an existing one, copy it first.
# Rollback: delete the include, `nginx -t`, reload.
# Confirm before running.
nginx -t && gp ngx -reload
```

## Gotchas

- **Never copy 6G rules into 7G configs.** They are incompatible and cause an
  Nginx syntax failure that can take every site on the server offline.
- **Custom rules only at server level.** Adding new custom rules uses the
  ruleset includes like `*7g-bad-bot-context.conf`; whitelisting works at server
  and site level.
- **Simplest fix first.** If a one-off action is blocked, toggle the offending
  ruleset off, run the action, toggle it back on, rather than maintaining a
  permanent whitelist.
- **OLS differs.** The 7G WAF has an OLS variant; the Nginx include paths here do
  not apply. See the OLS KB article.

## Unverified

- The exact ModSecurity CRS ruleset/version on current stacks. The default
  paranoia level is `1` (per-site env capture; `lib/waf.sh` reads it from the
  per-site `modsec/{site}-crs-paranoia-level.conf`). Confirm the ruleset version
  on the server before quoting it.

## Sources

- Using the 7G WAF — https://gridpane.com/kb/using-the-7g-web-application-firewall/
- The 7G WAF and OpenLiteSpeed — https://gridpane.com/kb/the-gridpane-7g-web-application-firewall-and-openlitespeed-ols/
- Using the GridPane 6G WAF — https://gridpane.com/kb/using-the-gridpane-6g-web-application-firewall/
- Using the ModSec WAF — https://gridpane.com/kb/using-the-gridpane-modsec-web-application-firewall/
