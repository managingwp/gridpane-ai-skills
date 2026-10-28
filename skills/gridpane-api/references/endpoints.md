# GridPane REST API

Two tiers of fact live here. Endpoint paths and request bodies come from the
GridPane API Postman collection — the official API documentation the KB points
to. Response shapes, pagination and error behaviour were verified by a live probe
on **2026-10-28** (75 primary sites, 238 domains, 98 system users on one account;
evidence in `gridpane-core/references/sources.md`). Verify the full endpoint list
in the collection before relying on any path.

## Base URL and auth

- Base URL: `https://my.gridpane.com/oauth/api/v1`
- Auth header: `Authorization: Bearer <token>`
- Token: created in GridPane **Settings > GridPane API > Create New Token**
  (Developer plan or above). Store it in `GRIDPANE_API_TOKEN`; never commit it.
- Content type for JSON bodies: `application/json`.
- Path parameters such as `{site.id}` are integers in the URIs.

Override the base URL for testing with `GRIDPANE_API_URL` (the wrapper defaults
to the URL above).

## Response shapes (verified 2026-10-28)

The list endpoints do **not** share a shape. Reading them the same way is the
single most expensive mistake in this API: the arrays are at different depths, so
an expression that works on `/site` silently yields an object (or nothing) on
`/domain`.

### `/domain` is nested

`GET /domain` puts the array at **`data.domains`**, adds a sibling object
`data.constants`, and puts `meta` and `links` at the **top level**, next to
`data`:

```json
{
  "data": {
    "domains": [
      {
        "id": 123456,
        "url": "example.com",
        "type": "primary",
        "site_id": 123457,
        "server_id": 1234,
        "is_ssl": false,
        "ssl_status": "failed",
        "is_wildcard": true,
        "primary_is_staging": false,
        "primary_staging_enabled": false,
        "primary_canary_enabled": true,
        "user_dns": {}
      }
    ],
    "constants": {}
  },
  "links": [],
  "meta": {"current_page": 1, "last_page": 1, "per_page": 500, "total": 238}
}
```

### `/site` and `/system-user` are flat

On `GET /site` and `GET /system-user`, `data` **is** the array:

```json
{"data": [{"id": 123457, "url": "example.com"}], "links": [], "meta": {}}
```

### Unwrapping the list

```bash
# [READ] The /domain unwrap: works because `data` is an object there.
jq '(.data.domains // .data // [])'
```

Use this everywhere the domain list is consumed — including at a cache-write
boundary, where the normalised array should be stored rather than the raw
envelope. Reading `.data` on `/domain` gives an object, so `.[]`, `length` and
CSV mappings produce an error, zero rows or a single garbage row instead of the
domains.

If one expression has to serve every list endpoint, add the optional-error guard
to `.data.domains`:

```bash
# [READ] Same result on nested /domain and flat /site or /system-user bodies.
jq '(.data.domains? // .data // [])'
```

The `?` matters: `//` replaces `null` and `false` but not errors, so the
unguarded `.data.domains` on a flat body fails with
`Cannot index array with string "domains"`. The plain
`(.data.domains // .data // [])` is correct for `/domain` only.

### Domain fields observed

| Field | Meaning |
|---|---|
| `id` | Domain id, used by `GET/PUT/DELETE /domain/{domain.id}`. |
| `url` | Hostname, without scheme. |
| `type` | `primary` or `alias` in the probe. Never `staging` or `canary` — see below. |
| `site_id` | The site record this domain belongs to. A staging domain points at a sibling site id that never appears in `/site`. |
| `server_id` | Server the site runs on. |
| `is_ssl`, `ssl_status` | SSL state (`ssl_status: "failed"` observed). |
| `is_wildcard` | Wildcard flag. |
| `primary_is_staging` | Boolean metadata about the primary record; **not** a staging enumerator. |
| `primary_staging_enabled`, `primary_canary_enabled` | Site feature flags; **not** staging enumerators. |
| `user_dns` | Per-domain DNS integration detail (object). |
| `constants` | Sibling of `domains` inside `data`. |

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
| [READ] | GET | `/site` | List **primary** sites (flat `data`). Staging sites are not included. |
| [READ] | GET | `/site/{site.id}` | One site. A staging site id returns 422. |
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
| [READ] | GET | `/domain` | List domains. **Nested payload**: array at `data.domains`, `meta` at top level. |
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
| [READ] | GET | `/system-user` | List system users across the account (flat `data`). |
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

## Staging sites (verified 2026-10-28)

`GET /site` returns **primary sites only**. A staging copy is a separate sibling
site record; the parent only hints at it with `staging_site_built_at`.

### Detect staging from the URL, not `.type`

The collection documents the domain `type` enum as
`primary, alias, redirect, staging, canary`. In the probe, across all 238 domains,
the observed values were **`primary` and `alias` only** — `staging.` and
`canary.` domains report `type: "primary"`. The only discriminator that worked is
the URL prefix:

```bash
# [READ] From the unwrapped domain array, count staging and canary domains.
jq '[ (.data.domains // .data // [])[]
      | select(.url | test("^(staging|canary)\\.")) ] | length'
```

Do not substitute the related booleans. `primary_is_staging` (74 true),
`primary_staging_enabled` (3 true) and `primary_canary_enabled` (21 true) do not
enumerate the staging sites — their counts do not correspond to the 149 staging
domains observed. Treat them as unrelated metadata.

### Discover them in bulk

One `GET /domain?per_page=500` request returned all 238 domains on a single page.
Filtering the URL prefix matched 149 domains, giving 149 distinct `site_id`, none
of which appeared in the `/site` list. That makes `/domain` the cheap bulk source
for staging discovery.

Do **not** walk parents with `GET /site/{parent_id}` looking for staging: it is
one rate-limited request per parent and it returns nothing useful (next section).

### Staging ids are not addressable or hydratable

- `GET /site/{staging_site_id}` → **HTTP 422**

  ```json
  {"error":{"message":"That site does not belong to the bearer of this access token. Unable to comply."}}
  ```

- `GET /site/{parent_id}` for a parent whose `staging_site_built_at` is set →
  **200, but `staging_site_id`, `staging_url` and `staging_site` are all
  `null`.** The list endpoint returns them as `null` for every record too.

Consequence: `php_version`, `nginx_caching`, `remote_bup`, `local_bup`,
`multisites`, `www`, `root`, `user_id` and `system_userid` are
**unavailable for staging sites**. Only the `/domain` fields are obtainable:
`id`, `url`, `is_ssl`, `ssl_status`, `server_id`, `is_wildcard` and the rest of
the domain record.

A 422 on a staging site id is **expected**, not an auth failure and not a bug. A
globally bad token behaves differently: it answers `302 → /login`.

### `/system-user` is not a staging source

`GET /system-user?per_page=500` returned 98 users, and each user's `.sites[]`
entries carry **only `{id, url}`** — no site fields. 34 staging URLs appeared
there, and all 34 are a strict subset of the 149 from `/domain` (115 were
domain-only, 0 system-user-only). Use `/domain` instead.

## Pagination, rate limits and error shapes

- List responses carry `meta.current_page`, `meta.last_page`, `meta.per_page` and
  `meta.total` as a **top-level sibling of `data`**, not inside `data`.
- `per_page=500` was accepted, and 238 domains fitted one page. The maximum
  accepted `per_page` is unverified.
- The API is aggressively rate limited. The probe hit HTTP 429 after a handful of
  requests:

  ```json
  {"error":{"code":429,"message":"Beep, Beep, you're going too fast..."}}
  ```

  Prefer bulk list endpoints over per-record fetches: one paginated `/domain`
  call replaces hundreds of `/site/{id}` calls and their 429 risk.

| Status | Meaning | Action |
|---|---|---|
| 422 | The record is not addressable by this token. Expected for staging site ids. | Stop for that record; do not retry, do not treat as a bad token. |
| 429 | Rate limited. | Back off; switch to a bulk list endpoint. |
| 302 → `/login` | The token or session is invalid globally. | Stop; check `GRIDPANE_API_TOKEN`. |

The wrapper retries 429 with back-off, so do not add your own retry loop on top.

## Safety

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
# [READ] Print just the domain array, whatever the envelope.
GRIDPANE_API_TOKEN=... skills/gridpane-api/scripts/gp-api.sh GET '/domain?per_page=500' \
  | jq '(.data.domains // .data // [])'
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

## Unverified

- The maximum accepted `per_page`, and the rate-limit headers and reset window
  (the probe recorded the 429 body, not the headers).
- Whether `type` can ever report `redirect`, `staging` or `canary` on another
  account: the enum is documented, but only `primary` and `alias` were observed.
- Whether a staging site's settings can be read through any other endpoint; the
  probe only established that `GET /site/{id}` cannot.
- Whether the OAuth token used by the collection differs from a personal API
  token in any way.

## Sources

- GridPane API Introduction and Postman Documentation — https://gridpane.com/kb/gridpane-api-introduction-and-postman-documentation/
- GridPane API Postman collection — https://documenter.getpostman.com/view/13664964/TVssjU7Z
- Collection JSON (public) — https://documenter.gw.postman.com/api/collections/13664964/TVssjU7Z
- Account Management (API token) — https://gridpane.com/knowledgebase/account-management/
- Live probe, 2026-10-28 — evidence in `gridpane-core/references/sources.md`

Last verified: 2026-10-28
