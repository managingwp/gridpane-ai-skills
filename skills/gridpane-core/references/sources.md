# Sources

Every GridPane-specific fact used in the skills is traced here. Re-check the page
before relying on a fact; GridPane changes over time.

All pages checked **2026-10-07** unless noted. Pages added on **2026-10-09** are
marked in the tables below. A maintainer-supplied capture of `/root/gridenv` from
a real GridPane server (2026-10-09) is the source for the server-state files in
`gridenv.md`; secret values were redacted before anything was written down.

## Core

| Topic | URL |
|---|---|
| GP-CLI Quick Reference (all gp commands) | https://gridpane.com/kb/gp-cli-quick-reference/ |
| GridPane Logs — locations and meaning | https://gridpane.com/kb/gridpane-logs-how-to-find-them-and-when-to-use-them/ |
| Useful Commands for Managing GridPane Servers | https://gridpane.com/kb/useful-commands-for-managing-gridpane-servers/ |
| The wp-config.php Location at GridPane | https://gridpane.com/kb/the-wp-config-php-location-at-gridpane/ |
| Configure Nginx (include paths, per-site vs server-wide) | https://gridpane.com/kb/configure-nginx/ |
| Adding Custom Nginx Rules for Plugins (general guide) | https://gridpane.com/kb/adding-custom-nginx-rules-for-plugins-a-general-guide/ |
| Configure PHP (`.user.ini`, per-site pool paths) | https://gridpane.com/kb/configure-php/ |
| Configure Redis | https://gridpane.com/kb/configure-redis/ |
| GridPane Servers and the /tmp Directory | https://gridpane.com/kb/gridpane-servers-and-the-tmp-directory/ |
| GP WP-CLI and Regular WP-CLI | https://gridpane.com/kb/gp-wp-cli/ |
| Set a GridPane site as the Default Site for Nginx | https://gridpane.com/kb/set-a-gridpane-site-as-the-default-site-for-nginx/ |
| GridPane API Introduction and Postman Documentation | https://gridpane.com/kb/gridpane-api-introduction-and-postman-documentation/ |
| Migrations, Cloning and wp-config.php (custom user-configs) | https://gridpane.com/kb/migrations-cloning-and-the-wordpress-configuration-file-wp-config-php/ |
| Configure Monit with GP-CLI (`/root/gridenv/monit.env`) | https://gridpane.com/kb/configure-monit-with-gp-cli/ *(added 2026-10-09)* |
| Nginoil (`/root/gridenv/nginx.env`) | https://gridpane.com/kb/nginoil-automatically-fix-nginx-syntax-errors/ *(added 2026-10-09)* |

## Referenced by later skills

| Topic | URL | Used by |
|---|---|---|
| Diagnosing 502 Errors | https://gridpane.com/kb/diagnosing-502-errors/ | incident-triage |
| Diagnosing 503 Errors | https://gridpane.com/kb/diagnosing-503-errors/ | incident-triage |
| Diagnosing HTTP 500 Internal Server Errors | https://gridpane.com/kb/diagnosing-http-500-internal-server-errors/ | incident-triage |
| Diagnosing Redirect Issues | https://gridpane.com/kb/diagnosing-redirect-issues/ | incident-triage |
| Diagnosing and Fixing SSL Certificate Issues | https://gridpane.com/kb/diagnosing-and-fixing-ssl-certificate-issues/ | incident-triage |
| Diagnosing Performance Issues and 504 Timeouts | https://gridpane.com/kb/diagnosing-performance-issues-and-504-timeouts/ | server-diagnostics |
| Using the MySQL Slow Log | https://gridpane.com/kb/using-the-mysql-slow-log/ | server-diagnostics |
| Using the PHP Slow Log | https://gridpane.com/kb/using-the-php-slow-log/ | server-diagnostics |
| Understanding Memory (RAM) Usage and Notifications | https://gridpane.com/kb/understanding-memory-ram-usage-and-notifications/ | server-diagnostics |
| Troubleshooting High Disk Space Usage | https://gridpane.com/kb/troubleshooting-high-disk-space-usage-and-locating-large-files/ | server-diagnostics |
| Using the GridPane 7G WAF | https://gridpane.com/kb/using-the-7g-web-application-firewall/ | security |
| Default GridPane Security and Additional Options | https://gridpane.com/kb/default-gridpane-security-and-additional-options/ | security |
| Configuring Fail2Ban to Prevent Brute Force Attacks | https://gridpane.com/kb/configuring-fail2ban-to-prevent-brute-force-attacks/ | security |
| Using Fail2Ban with Cloudflare | https://gridpane.com/kb/using-fail2ban-with-cloudflare/ | security |
| Using Cloudflare with GridPane | https://gridpane.com/kb/using-cloudflare-with-gridpane/ | security |
| Updating Cloudflare Real IPs | https://gridpane.com/kb/updating-cloudflare-real-ips/ | security |
| GridPane FastCGI Page Caching | https://gridpane.com/kb/using-gridpane-nginx-fastcgi-page-caching/ | wordpress |
| GridPane Redis Page Caching | https://gridpane.com/kb/using-gridpane-nginx-redis-page-caching/ | wordpress |
| GridPane Redis Object Caching | https://gridpane.com/kb/using-gridpane-redis-object-caching/ | wordpress |
| Diagnosing Caching Issues (both header families) | https://gridpane.com/kb/diagnosing-caching-issues/ | wordpress *(added 2026-10-09)* |
| Exclude a Page or Cookie from Nginx Server Caching | https://gridpane.com/kb/exclude-a-page-from-server-caching/ | wordpress *(added 2026-10-09)* |
| How to Clear Your Website Caches (all methods) | https://gridpane.com/kb/how-to-clear-your-website-caches-all-methods/ | wordpress |
| WP-Cron and GridPane's GP-Cron | https://gridpane.com/kb/wp-cron-and-gridpanes-gp-cron-updated/ | wordpress |
| Working with WooCommerce | https://gridpane.com/kb/working-with-woocommerce/ | wordpress |
| WP Debug and Query Monitor | https://gridpane.com/kb/wordpress-debug-and-query-monitor/ | wordpress |
| Temporary URLs for Migrations and Development | https://gridpane.com/kb/temporary-urls-for-migrations-and-development/ | wordpress |
| Local Website Backups | https://gridpane.com/kb/local-website-backups/ | gp-cli |
| Remote Website Backups | https://gridpane.com/kb/remote-website-backups/ | gp-cli |
| How to Add Additional System Users to a Website | https://gridpane.com/kb/how-to-add-additional-system-users-to-a-website/ | wordpress |

## Tooling (`gridpane-tooling`)

The primary source is a maintainer-supplied snapshot of the scripts GridPane
deploys to `/usr/local/bin` (plus `/etc/monit`), kept locally at `tmp/gpcli`
(gitignored) and mirrored by the maintainer's `gpcli` repo. Facts cite `file:line`
in that snapshot; the scripts are GridPane's copyright and are not rehosted
here.

| Snapshot file | Used for |
|---|---|
| `tmp/gpcli/README.md` | Deployed layout, `gp` CLI areas, wrappers, `lib/` modules, `gridpane.ver` |
| `tmp/gpcli/AGENTS.md` | Snapshot conventions, `sync.sh` mirroring |
| `tmp/gpcli/usr/local/bin/gp` | Dispatcher, sourcing, dispatch labels, unknown-command exit `187` |
| `tmp/gpcli/usr/local/bin/gpupdate` | Update model, `/run/gridpane` lock |
| `tmp/gpcli/usr/local/bin/lib/*.sh` | Path references (`/opt/gridpane`, `/root/gridcreds`, `/var/log`, `/etc/cron.d`, `/etc/logrotate.d`) |
| `tmp/gpcli/etc/monit/conf.d/programs` | Monit program checks and `gpmonitor` exec pattern |
| `tmp/gpcli/docs/monit-slack-notifications.md` | monit → `gpmonitor` → GridPane API → Slack chain |

| Topic | URL | Used by |
|---|---|---|
| GP-CLI Quick Reference | https://gridpane.com/kb/gp-cli-quick-reference/ | tooling |
| Useful Commands for Managing GridPane Servers | https://gridpane.com/kb/useful-commands-for-managing-gridpane-servers/ | tooling |
| GridPane Logs — locations and meaning | https://gridpane.com/kb/gridpane-logs-how-to-find-them-and-when-to-use-them/ | tooling |
| GridPane KB REST feed (`kb` post type, 387 posts) | https://gridpane.com/wp-json/wp/v2/kb | tooling |
| GridPane KB categories (107 terms) | https://gridpane.com/wp-json/wp/v2/kbcategories | tooling |
| GridPane sitemap (KB enumeration fallback for the docs manifest) | https://gridpane.com/sitemap.xml | tooling |
| GridPane changelog (Upvoty-backed SPA; captured via its public JSON API) | https://roadmap.gridpane.com/changelog | tooling |

The KB REST routes were checked **2026-10-21**: `X-WP-Total: 387`, matching the
sitemap's 387 `/kb/` URLs, and `robots.txt` disallows only `/wp-admin/`. The
routes are public today but are not a stability guarantee, which is why the
sitemap path is kept as `--source sitemap`.

Date model, checked **2026-10-21** on one article: REST `modified`/`date` are
site-local (UTC-4) while `modified_gmt`/`date_gmt` are UTC; the page's
`<meta article:modified_time>` and JSON-LD `dateModified` and the sitemap
`lastmod` all equal `modified_gmt`. The site sends **no `Last-Modified` or
`ETag`** and answers no `304`s, so change detection uses the REST probe rather
than a conditional request (`gridpane-tooling/references/docs.md`).

## OpenLiteSpeed (`gridpane-core/references/ols.md`)

All checked **2026-10-19**. Snapshot files: `tmp/gpcli/usr/local/bin/gpols`,
`ols`, `lib/ols/source/*.sh`, `lib/ols/7g/*`,
`etc/monit/conf.d/openlitespeed`.

| Topic | URL |
|---|---|
| Getting Started with GridPane OpenLiteSpeed (OLS) | https://gridpane.com/kb/getting-started-with-openlitespeed-ols/ |
| OLS Caching and the LiteSpeed Cache Plugin (LSCache) | https://gridpane.com/kb/openlitespeed-ols-caching-and-the-litespeed-cache-plugin-lscache/ |
| The GridPane 7G WAF and OpenLiteSpeed (OLS) | https://gridpane.com/kb/the-gridpane-7g-web-application-firewall-and-openlitespeed-ols/ |
| Allow or Deny IP Addresses on OpenLiteSpeed | https://gridpane.com/kb/allow-or-deny-ip-addresses-on-openlitespeed/ |
| How to Add Your Own Custom Headers on OpenLiteSpeed | https://gridpane.com/kb/how-to-add-your-own-custom-headers-on-openlitespeed/ |
| How to Create Server-Level Redirects on OpenLiteSpeed (OLS) | https://gridpane.com/kb/how-to-create-server-level-redirects-on-openlitespeed-ols/ |
| How to Configure OpenLiteSpeed (OLS) Log Retention | https://gridpane.com/kb/how-to-configure-openlitespeed-ols-log-retention/ |
| Set Custom Expires by Type on OpenLiteSpeed (OLS) | https://gridpane.com/kb/set-custom-expires-by-type-on-openlitespeed-ols/ |
| Additional Security Measure Whitelisting on OpenLiteSpeed (OLS) | https://gridpane.com/kb/additional-security-measure-whitelisting-on-openlitespeed-ols/ |
| Country-Specific Redirects with GeoIP on OpenLiteSpeed (OLS) Servers | https://gridpane.com/kb/country-specific-redirects-with-geoip-on-openlitespeed-ols-servers/ |

## Non-GridPane references

| Topic | URL |
|---|---|
| GridPane API Postman documentation | https://documenter.getpostman.com/view/13664964/TVssjU7Z |
| GridPane Knowledge Base home | https://gridpane.com/kb/ |
