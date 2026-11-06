# Sources

Every GridPane-specific fact used in the skills is traced here. Re-check the page
before relying on a fact; GridPane changes over time.

All pages checked **2026-10-07** unless noted. Pages added on **2026-10-09** are
marked in the tables below. Four citations were re-pointed on **2026-11-06**
after the KB renamed the articles: the Cloudflare guide, the 6G WAF guide and the
two Nginx page-caching guides all dropped `gridpane` from their slugs for shorter
ones. A maintainer-supplied capture of `/root/gridenv` from a real GridPane
server (2026-10-09) is the source for the server-state files in `gridenv.md`;
secret values were redacted before anything was written down.

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
| Using the GridPane 6G WAF | https://gridpane.com/kb/using-the-6g-web-application-firewall/ | security |
| Default GridPane Security and Additional Options | https://gridpane.com/kb/default-gridpane-security-and-additional-options/ | security |
| Configuring Fail2Ban to Prevent Brute Force Attacks | https://gridpane.com/kb/configuring-fail2ban-to-prevent-brute-force-attacks/ | security |
| Using Fail2Ban with Cloudflare | https://gridpane.com/kb/using-fail2ban-with-cloudflare/ | security |
| Using Cloudflare with GridPane | https://gridpane.com/kb/using-cloudflare-api-integration/ | security |
| Updating Cloudflare Real IPs | https://gridpane.com/kb/updating-cloudflare-real-ips/ | security |
| GridPane FastCGI Page Caching | https://gridpane.com/kb/using-nginx-fastcgi-page-caching/ | wordpress |
| GridPane Redis Page Caching | https://gridpane.com/kb/using-nginx-redis-page-caching/ | wordpress |
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
| `tmp/gpcli/usr/local/bin/gpbup`, `gpbup2`, `lib/gpbup.sh` | Backup wrapper and `gpbup::main` arms (`-run-single-site`, `-single-site`, `-local-single-site`, `-purge`), `/etc/cron.d/backup-*` line shape, `Local-Backups:ON` prerequisite, local disk threshold, task-spooler queue socket, `gp-automated` revision tag |
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

## Missing-backup discovery evidence (2026-10-23)

Maintainer-supplied output from one GridPane server: creation/deletion and remote
configuration commands in `gridpane.log`; `backup.log` initialization,
available-backups payloads and enabled-state checks; local snapshot search;
sanitized Duplicacy preferences; Duplicacy **2.7.2** help and successful targeted
and all-ID Wasabi listings. Client identifiers, buckets, UUIDs and credentials
are intentionally not retained here.

- Verified observations: local and remote snapshot IDs differed; recreation
  retained the local ID but changed remote destination; two distinct buckets
  existed in one region; empty targeted/all-ID listings returned 0, while other
  sites' revisions could be listed in another bucket. Initialization alone did
  not supply a completed revision; historical checks reported backups disabled.
- Scope: supports `gridpane-gp-cli/references/missing-backups.md`, not a universal
  ID/bucket naming rule, proof of global absence, or an explanation of setup
  failure. Original remote configuration-to-bucket mapping remains unverified.
- Local cache/keyring effects and pre/post-hook suppression were cross-checked
  against Duplicacy's `listSnapshots`/`setGlobalOptions` implementation:
  https://github.com/gilbertchen/duplicacy/blob/v2.7.2/duplicacy/duplicacy_main.go
  (checked 2026-10-23 against the matching upstream release tag).

## GridPane API payload and staging evidence (2026-10-28)

Maintainer-supplied live probe of the GridPane REST API with a valid token on one
account, read-only GETs only: **75 primary sites**, **238 domains**, **98 system
users**. Real domains, ids and the token are intentionally not retained here; the
ids in the skills are illustrative.

- **`/domain` is nested.** The array is at `data.domains`, `data` also carries
  `constants`, and `meta`/`links` are top-level siblings of `data`. `GET /site`
  and `GET /system-user` are flat (`data` is the array). One unwrap covers both:
  `(.data.domains // .data // [])`.
- **Domain `.type` did not report staging.** Across all 238 domains the observed
  values were `primary` and `alias` only; `staging.` and `canary.` domains report
  `type: "primary"`. The documented enum (`primary, alias, redirect, staging,
  canary`) is not what this endpoint produced on this account.
- **Staging domains are separate site records.** The URL prefix filter
  `^(staging|canary)\.` matched 149 of 238 domains, giving 149 distinct `site_id`,
  none of which appear in the `/site` list. `primary_is_staging` (74 true),
  `primary_staging_enabled` (3 true) and `primary_canary_enabled` (21 true) do not
  enumerate them.
- **Staging ids are not addressable.** `GET /site/{staging_site_id}` returns HTTP
  422 "That site does not belong to the bearer of this access token"; `GET
  /site/{parent_id}` for a parent with `staging_site_built_at` set returns 200
  with `staging_site_id`, `staging_url` and `staging_site` all null, as does the
  list endpoint for every record. Site settings are therefore unavailable for
  staging sites.
- **`/system-user` is redundant for staging discovery.** Its per-user `.sites[]`
  entries carry only `{id, url}`; 34 staging URLs appeared there and all 34 are a
  strict subset of the 149 from `/domain`.
- **Rate limiting is aggressive.** HTTP 429 arrived after a handful of requests,
  body "Beep, Beep, you're going too fast...".

Scope: one account on one date, so the `.type` finding is "these values were
observed", not a claim that the documented enum can never appear, and the counts
describe this account only. Supports `gridpane-api/references/endpoints.md`; it
does not establish the maximum accepted `per_page`, the rate-limit headers or the
reset window.

## Backup queue evidence (2026-11-04)

Maintainer-supplied `ps` and `tsp` output from a root shell on one GridPane
server, read-only: nothing was changed on the box. The site is written
`example.com` and the remote provider `{storage}`; the hostname and address are
intentionally not retained here.

- A queued scheduled-form backup was alive as
  `tsp -L backups /usr/local/bin/gp backup {site} -single-site {storage}` — the
  wrapper's resolved spelling, under task-spooler.
- That job was still alive after four days with `0:00` CPU time.
- Two further resident processes were present: `tsp -L backup` and `tsp -s`.
- `tsp -L backups` on the **default** socket printed the header and no rows —
  `ID   State      Output               E-Level  Times(r/u/s)   Command [run=0/1]`
  — while the job above was alive. The backup queue is on its own socket, so
  this listing answered a different queue.

Scope: the capture did not include `TS_SOCKET`/`TS_SLOTS` for the live job,
`tsp -l` on the backup socket, or `tsp -i`, so it does **not** establish that
job's socket path, that socket's slot count, or what the `tsp -L backup` and
`tsp -s` processes are. Those are recorded in `OPEN-QUESTIONS.md`; the procedure
they support is `gridpane-gp-cli/references/backups.md`.

## MariaDB 11.8, dump generations and refused restores (2026-11-05)

Two source classes here. Facts about the deployed scripts are traced to the
`tmp/gpcli` snapshot captured 2026-10-14. The vector-search facts come from
GridPane staff answers on the community forum and are **not** in that snapshot,
so they are recorded as unverified (`OPEN-QUESTIONS.md`) rather than used as
guidance.

| Fact | Source |
|---|---|
| Database is chosen per server as `percona` or `mariadb`; version follows the OS stack | `gridpane-api/references/endpoints.md`; `lib/gridpane.sh:157-190` |
| Version tokens `percona84`, `percona`, `mariadb118`, `mariadb`, and the 10.11 vs 11.8 banner formats | `lib/gridpane.sh:151-190` |
| `utf8mb4_0900_*` absent on MariaDB 10.11; `utf8mb4_uca1400_*` absent on Percona | `lib/gridpane.sh:8316-8345` (collation preflight comments and probes) |
| Two mydumper generations, the `.gp-dump-version` manifest, and the measured mutual-unloadability results (`rc=139`, `rc=134`) | `lib/gridpane.sh:7740-7790` |
| Per-generation lock flags, `--clear`, and `--trx-tables=0` | `lib/gridpane.sh:9000-9040` |
| `/root/mydumper.timeout` and `/root/myloader.timeout`, default 10800, non-numeric falls back | `lib/clone.sh:820-833`, `lib/clone.sh:5899-5912`, `lib/gpbup.sh:5297-5310` |
| Restore refusal before the database drop: `Restore Issue` notification, `return 187`, dump preservation | `lib/restore.sh:5446-5482` |
| `restore::preserve_db_dump` reason codes (`loader`, `collation`, `dbcheck`, `invalid`, `import`) and its containment checks | `lib/restore.sh:4847-4870` |
| Clone-side collation preflight (`1` = refuse) and the `/root/allow.collation.mismatch` override | `lib/clone.sh:9533-9562` |
| `Clone Refused -- …` notification family, exit 187 | `lib/clone.sh:5-21` |
| MariaDB 10.11 on Ubuntu 22.04/24.04; MariaDB 11.8 and Percona 8.4 on Ubuntu 26.04 | https://gridpane.com/kb/database-versions-on-ubuntu-26-04-what-changes-and-why/ (checked 2026-11-06); originally the community forum, staff reply 2026-09-22 |
| 26.04 ships one mydumper build per database family; Percona and MariaDB are no longer interchangeable, so keep a move on the same engine | https://gridpane.com/kb/database-versions-on-ubuntu-26-04-what-changes-and-why/ (checked 2026-11-06) |
| Migrating to 26.04: same web stack and same database type, Migrately or Server Clone, extra Redis steps from 18.04/20.04 | https://gridpane.com/kb/migrating-to-ubuntu-26-04-what-you-need-to-know/ (checked 2026-11-06) |
| `VECTOR` type and vector indexes need MariaDB 11.7+; Percona has no vector type; vector restores load one thread per table, rebuild the index, and use a 16 MB default vector index cache | Same thread, staff reply 2026-09-25 — **unverified against code** |

## Non-GridPane references

| Topic | URL |
|---|---|
| GridPane API Postman documentation | https://documenter.getpostman.com/view/13664964/TVssjU7Z |
| GridPane Knowledge Base home | https://gridpane.com/kb/ |
| task-spooler `tsp(1)` (`-L` label, `-l` list, `-o`/`-c`/`-t` output, `-p` pid, `-k` SIGTERM to the process group) | https://manpages.ubuntu.com/manpages/noble/man1/tsp.1.html |
