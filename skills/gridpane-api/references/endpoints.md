# GridPane REST API

Facts here are from the GridPane API Postman collection (the official API
documentation the KB points to) and community client projects. Verify the full
endpoint list in the collection before relying on any path.

## Base URL and auth

- Base URL: `https://my.gridpane.com/oauth/api/v1`
- Auth header: `Authorization: Bearer <token>`
- Token: created in GridPane **Settings > GridPane API > Create New Token**
  (Developer plan or above). Store it in `GRIDPANE_API_TOKEN`; never commit it.
- Content type for JSON bodies: `application/json`.
- Path parameters such as `{site.id}` are integers in the URIs.

Override the base URL for testing with `GRIDPANE_API_URL` (the wrapper defaults
to the URL above).

## Verified endpoints (backups)

These are documented in the Postman collection:

| Label | Method | Endpoint | Purpose |
|---|---|---|---|
| [WRITE] | PUT | `/backups/schedule/site/{site.id}` | Update a site's backup schedule. |
| [WRITE] | PUT | `/backups/prune-schedule/{site.id}` | Update the prune schedule (`backup_type`, `retain_days`, `prune_schedule`). |
| [DESTRUCTIVE] | PUT | `/backups/purge/{site.id}` | Purge one backup (`backup_source`, `backup_type`, `backup`). |
| [DESTRUCTIVE] | PUT | `/backups/purge-range/{site.id}` | Purge a range (`backup_source`, `from_backup`, `to_backup`). |
| [DESTRUCTIVE] | DELETE | `/backups/integrations/{site.id}` | Detach a remote backup integration. |

Request body fields (from the collection) include `backup_source` accepting
`local`, `aws-s3`, `backblaze`, `dropbox`, `wasabi`; `backup_type` accepting
`manual` or `automatic`; and `bup_schedule` accepting `hourly`, `daily`,
`weekly`, `monthly`.

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

Not verified from the KB. Confirm from the collection and record here before
relying on them. Until then:

- Treat list responses as you find them; do not assume a wrapper key.
- The wrapper backs off on 429; do not hammer the API in a loop.
- On error the API returns a non-2xx status; the wrapper surfaces the body and a
  non-zero exit.

## Unverified

- The list endpoints for **servers** and **sites**, and their exact response
  field names. `gp-inventory.sh` therefore requires the paths to be supplied and
  uses a best-effort CSV mapping. Confirm from the Postman collection.
- Pagination scheme and rate-limit headers.
- The complete endpoint catalogue beyond the backups endpoints above.

## Sources

- GridPane API Introduction and Postman Documentation — https://gridpane.com/kb/gridpane-api-introduction-and-postman-documentation/
- GridPane API Postman collection — https://documenter.getpostman.com/view/13664964/TVssjU7Z
- Account Management (API token) — https://gridpane.com/knowledgebase/account-management/
