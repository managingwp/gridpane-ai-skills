---
name: gridpane-api
description: >-
  Use for fleet-wide GridPane actions through the REST API: list servers and
  sites, export inventory, call endpoints. Read-only by default; mutating calls
  need confirmation.
---

# gridpane-api

Fleet-wide work through the GridPane REST API. Use it for inventory questions and
for documented API actions; use the SSH-based skills for single-server work.

Load `gridpane-core` first. Endpoint details, auth and the verified endpoint list
are in `references/endpoints.md`.

## Prerequisites

- `GRIDPANE_API_TOKEN` set in the environment. Never commit or echo it.
- Optionally `GRIDPANE_API_URL` to override the base URL (default
  `https://my.gridpane.com/oauth/api/v1`).
- `bash`, `curl` and `jq` on the machine running the scripts.
- A real API token needs a Developer plan or above.

## Workflow

1. **Read before you act.** Start with a GET to understand the fleet.
2. **Prefer bulk list endpoints over per-record fetches.** The API rate-limits
   aggressively (HTTP 429 after a handful of requests), so one paginated
   `/domain` call beats hundreds of `/site/{id}` calls. Staging inventory comes
   from `/domain`, not from parent site records.
3. **Answer fleet questions from inventory**, not by sweeping servers one by one.
4. **For a mutating call:** show the exact request, the target (one server/site or
   the whole account), the effect and whether it is reversible; wait for
   confirmation; then pass `--yes`.
5. **Never run fleet-wide destructive actions** without per-target confirmation.

## Commands

```bash
# [READ] Call any endpoint. Method defaults to GET.
GRIDPANE_API_TOKEN=... skills/gridpane-api/scripts/gp-api.sh GET /backups/integrations/42
```

```bash
# [READ] Export servers and sites to JSON and CSV. The list endpoints are
# verified from the API collection and default to /server?summary=true and /site.
GRIDPANE_API_TOKEN=... skills/gridpane-api/scripts/gp-inventory.sh --out-dir out
```

```bash
# [READ] Override the list endpoints if the API changes.
GRIDPANE_API_TOKEN=... skills/gridpane-api/scripts/gp-inventory.sh \
  --servers-path '/server?summary=true' --sites-path /site --out-dir out
```

```bash
# [WRITE] Mutating calls require --yes.
skills/gridpane-api/scripts/gp-api.sh PUT /backups/prune-schedule/42 \
  --data '{"backup_type":"local","retain_days":30,"prune_schedule":0}' --yes
```

Fleet questions, answered from the exported inventory:

```bash
# [READ] Which sites run PHP 8.1? (adjust the column to the confirmed CSV shape)
awk -F',' 'NR==1 || $3 ~ /8\.1/' out/inventory.csv
```

## Verify

- The wrapper exits 0 on success and non-zero on HTTP 4xx/5xx.
- Confirm a mutation landed by reading the object back with a GET.
- Confirm the token never appears in captured output.

## Rollback

- API changes are per endpoint. Set the previous value back with the reciprocal
  call, or reverse the change where the API supports it.
- Purging backups ([DESTRUCTIVE]) cannot be undone; verify the target and range
  before running, and confirm a usable backup remains.

## Gotchas

- **No fleet-wide mutating actions without per-target confirmation.** One wrong
  `all`-style call can affect every site in the account.
- **The token is a secret.** It is read from the environment only and never
  printed. Do not paste it into a transcript or commit it.
- **Endpoints are actively developed.** The API docs warn that endpoints evolve;
  re-check the collection when something breaks.
- **`/domain` is nested; `/site` and `/system-user` are flat.** The list
  endpoints do not share a shape. Read the domain array with
  `(.data.domains // .data // [])` (`(.data.domains? // .data // [])` when one
  expression serves both), and remember `meta` is a sibling of `data`, not
  inside it (`references/endpoints.md`).
- **`.type` never reports `staging` or `canary`.** `staging.` and `canary.`
  domains return `type: "primary"`; detect them from the URL prefix
  `^(staging|canary)\.`, never from `.type` or the `primary_*` booleans.
- **Staging sites come from one bulk request.** `GET /site` lists primary sites
  only; a staging copy is a separate record enumerated from
  `/domain?per_page=500`. Do not iterate `GET /site/{parent}` — it is one
  rate-limited request per parent and returns null staging fields.
- **A 422 on a staging site id is expected.** It means "not addressable by this
  token", not a bad token. A globally bad token answers `302 → /login` instead.
- **Rate limits.** The wrapper backs off on HTTP 429; prefer bulk list endpoints
  over per-record fetches.
- **Tests never touch the live API.** `tests/scripts/` runs against local
  fixtures.

## Sources

- GridPane API Introduction and Postman Documentation — https://gridpane.com/kb/gridpane-api-introduction-and-postman-documentation/
- GridPane API Postman collection — https://documenter.getpostman.com/view/13664964/TVssjU7Z
- Account Management (API token) — https://gridpane.com/knowledgebase/account-management/
- Response shapes, pagination and error behaviour: live probe 2026-10-28,
  evidence in `skills/gridpane-core/references/sources.md`.

See `references/endpoints.md`. Last verified: 2026-10-28
