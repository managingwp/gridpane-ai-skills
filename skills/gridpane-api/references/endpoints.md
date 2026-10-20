# GridPane REST API

Facts here are from the GridPane API Postman collection (the official API
documentation the KB points to). Verify the full endpoint list in the collection
before relying on any path.

## Base URL and auth

- Base URL: `https://my.gridpane.com/oauth/api/v1`
- Auth header: `Authorization: Bearer <token>`
- Token: created in GridPane **Settings > GridPane API > Create New Token**
  (Developer plan or above). Store it in `GRIDPANE_API_TOKEN`; never commit it.
- Content type for JSON bodies: `application/json`.
- Path parameters such as `{site.id}` are integers in the URIs.

Override the base URL for testing with `GRIDPANE_API_URL` (the wrapper defaults
to the URL above).

## Endpoint catalogue

Every row carries a label. The collection has folders for `user`, `server`,
`site`, `domain`, `system-user`, `teams`, `bundles` and `backups`.

### user

| Label | Method | Endpoint | Purpose |
|---|---|---|---|
| [READ] | GET | `/user` | Current user account. |
| [READ] | GET | `/user/integrations` | Integrations and their IDs. |
| [WRITE] | POST | `/user` | Create a user (agency only). |

### server

| Label | Method | Endpoint | Purpose |
|---|---|---|---|
| [READ] | GET | `/server` | List servers. |
| [READ] | GET | `/server?summary=true` | List servers, summarised. |
| [READ] | GET | `/server/{server.id}` | One server. |
| [READ] | GET | `/server/{server.id}?summary=true` | One server, summarised. |
| [READ] | GET | `/server/{provider}/plans` | Provider plans (`digitalocean`, `vultr`, `linode`, `aws-lightsail`, `upcloud`). |
| [READ] | GET | `/server/build-progress/{server.id}` | Build progress. |
| [WRITE] | POST | `/server/{provider}` | Create a server. |
| [WRITE] | POST | `/server/custom` | Create a custom server. |
| [WRITE] | PUT | `/server/{server.id}` | Clone all sites, update timezone, security-update settings or the backups system. |
| [DESTRUCTIVE] | DELETE | `/server/{server.id}` | Delete a server. |

**Server summary fields** (documented in the collection): `id`, `label`, `ip`,
`region`, `sub_id` (provider id), `subdomain` (for monit/phpma sites),
`webserver` (`nginx` or `openlitespeed`), `database` (`percona` or `mariadb`).

### site

| Label | Method | Endpoint | Purpose |
|---|---|---|---|
| [READ] | GET | `/site` | List sites. |
| [READ] | GET | `/site/{site.id}` | One site. |
| [WRITE] | POST | `/site` | Create a site (`url`, `server_id`, …). |
| [WRITE] | PUT | `/site/{site.id}` | Change a site setting (PHP, caching, WAF, suspend, clone, …). |
| [WRITE] | PUT | `/site/run-wp-cli/{site.id}` | Run WP-CLI on the site. |
| [WRITE] | PUT | `/site/add-wp-users/{site.id}` | Add WP users. |
| [DESTRUCTIVE] | DELETE | `/site` | Delete a site (`site_id` **and** `server_id` in the body). |
| [DESTRUCTIVE] | DELETE | `/site/{site_id}` | Delete a site by id (the collection warns this is more dangerous). |

Documented `PUT /site/{site.id}` body keys include:

- PHP: `php_version` (`7.2`–`8.x`), `pm` (`static`/`dynamic`/`ondemand`),
  `pm_max_children`, `pm_max_requests`, `pm_start_servers`, `pm_min_spare_servers`,
  `pm_max_spare_servers`, `pm_process_idle_timeout`, `php_slowlog_timeout`,
  `php_slowlog_trace_depth`, `max_execution_time`, `memory_limit`,
  `post_max_size`, `upload_max_filesize`, `max_input_vars`, `max_input_time`,
  `max_file_uploads`, `session_cookie_lifetime`, `session_gc_maxlifetime`,
  `short_open_tag`.
- Caching: `nginx_caching` (`redis`/`fastcgi`/`none`), `nginx_caching_ttl`
  (integer), `object_caching` (boolean), `clear_cache` (`page`/`object`/`all`).
- WAF / hardening: `six_g_waf`, `seven_g_waf`, `mod_sec_waf` (booleans),
  `http_auth` (boolean), `debug` (boolean).
- Lifecycle: `suspend_site` (boolean), `system_user_id` or `username`,
  `clone_to_server`, `clone_over_to_server`.

### domain

| Label | Method | Endpoint | Purpose |
|---|---|---|---|
| [READ] | GET | `/domain` | List domains. |
| [READ] | GET | `/domain/{domain.id}` | One domain. |
| [WRITE] | POST | `/domain` | Add an add-on domain (`domain_url`, `site_id`, `server_id`). |
| [WRITE] | PUT | `/domain/{domain.id}` | Primary swap, SSL, routing, wildcard or DNS integration. |
| [DESTRUCTIVE] | DELETE | `/domain/{domain.id}` | Delete a domain. |

Documented `PUT /domain/{domain.id}` body keys: `switch_to_primary_type` (`true`
only), `ssl` (boolean), `wildcard` (boolean), `routing` (`none`/`www`/`root`),
`dns_management`.

### system-user

| Label | Method | Endpoint | Purpose |
|---|---|---|---|
| [READ] | GET | `/system-user` | List system users across the account. |
| [READ] | GET | `/system-user/{id}` | One system user. |
| [WRITE] | POST | `/system-user` | Create a system user. |
| [WRITE] | PUT | `/system-user/{id}` | Update a system user. |
| [DESTRUCTIVE] | DELETE | `/system-user/{id}` | Delete a system user. |

### backups

| Label | Method | Endpoint | Purpose |
|---|---|---|---|
| [WRITE] | PUT | `/backups/schedule/site/{site.id}` | Update a site's backup schedule. |
| [WRITE] | PUT | `/backups/prune-schedule/{site.id}` | Update the prune schedule (`backup_type`, `retain_days`, `prune_schedule`). |
| [DESTRUCTIVE] | PUT | `/backups/purge/{site.id}` | Purge one backup (`backup_source`, `backup_type`, `backup`). |
| [DESTRUCTIVE] | PUT | `/backups/purge-range/{site.id}` | Purge a range (`backup_source`, `from_backup`, `to_backup`). |
| [DESTRUCTIVE] | DELETE | `/backups/integrations/{site.id}` | Detach a remote backup integration. |

Request body fields include `backup_source` (`local`, `aws-s3`, `backblaze`,
`dropbox`, `wasabi`), `backup_type` (`manual` or `automatic`), and `bup_schedule`
(`hourly`, `daily`, `weekly`, `monthly`).

### Safety

Every **[WRITE]**/**[DESTRUCTIVE]** call follows
`gridpane-core/references/safety.md`: state the effect, target and reversibility,
confirm, and verify a backup exists before any purge. Rollback: set values back
with the reciprocal call where the API supports it; a backup purge
([DESTRUCTIVE]) cannot be undone.

## Using the wrapper

```bash
# [READ] GET a path and print the JSON body.
GRIDPANE_API_TOKEN=... skills/gridpane-api/scripts/gp-api.sh GET /backups/integrations/42
```

```bash
# [WRITE] A mutating call requires --yes, and prints the body of the response.
skills/gridpane-api/scripts/gp-api.sh PUT /backups/prune-schedule/42 \
  --data '{"backup_type":"local","retain_days":30,"prune_schedule":0}' --yes
```

```bash
# [DESTRUCTIVE] Purging backups is irreversible; confirm the site id and range.
skills/gridpane-api/scripts/gp-api.sh PUT /backups/purge/42 \
  --data '{"backup_source":"wasabi","backup_type":"manual","backup":"2021-12-25 08:59"}' --yes
```

The wrapper:

- reads the token from `GRIDPANE_API_TOKEN` only and never prints it;
- defaults to GET; any non-GET method requires `--yes`;
- retries on HTTP 429 with back-off;
- exits non-zero on HTTP 4xx/5xx after printing the body.

## Pagination, rate limits and error shapes

- The collection documents **no pagination parameters** on the list endpoints;
  they appear to return the full collection. Confirm against a live response
  before paginating.
- Rate-limit headers and limits are unverified.
- On error the API returns a non-2xx status; the wrapper surfaces the body and a
  non-zero exit.

## Unverified

- The **site**, **domain** and **system-user** list response field names: only
  the server summary fields are documented. Capture one live response to confirm
  before relying on the CSV mapping in `gp-inventory.sh`.
- Pagination and rate-limit headers.
- Whether the OAuth token used by the collection differs from a personal API
  token in any way.

## Sources

- GridPane API Introduction and Postman Documentation — https://gridpane.com/kb/gridpane-api-introduction-and-postman-documentation/
- GridPane API Postman collection — https://documenter.getpostman.com/view/13664964/TVssjU7Z
- Collection JSON (public) — https://documenter.gw.postman.com/api/collections/13664964/TVssjU7Z
- Account Management (API token) — https://gridpane.com/knowledgebase/account-management/

Last verified: 2026-10-19
