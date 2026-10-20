---
name: gridpane-api
description: >-
  Use for fleet-wide GridPane questions and actions through the GridPane REST
  API: listing servers and sites, answering "which sites run PHP 8.1?", exporting
  an inventory, or calling documented endpoints (for example backup schedules or
  purges) with a token in GRIDPANE_API_TOKEN. Read-only by default; mutating
  calls need explicit confirmation and there are no unattended fleet-wide
  actions. Do not use for single-server SSH work (use gridpane-server-diagnostics
  or gridpane-gp-cli), and do not commit or print the API token.
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
2. **Answer fleet questions from inventory**, not by sweeping servers one by one.
3. **For a mutating call:** show the exact request, the target (one server/site or
   the whole account), the effect and whether it is reversible; wait for
   confirmation; then pass `--yes`.
4. **Never run fleet-wide destructive actions** without per-target confirmation.

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
- **List endpoints are verified; site response fields are not.** The servers and
  sites paths come from the API collection, and the server summary fields are
  documented there, but the site CSV mapping is best-effort until a live response
  is captured (`references/endpoints.md`).
- **Rate limits.** The wrapper backs off on HTTP 429; do not loop aggressively.
- **Tests never touch the live API.** `tests/scripts/` runs against local
  fixtures.

## Sources

- GridPane API Introduction and Postman Documentation — https://gridpane.com/kb/gridpane-api-introduction-and-postman-documentation/
- GridPane API Postman collection — https://documenter.getpostman.com/view/13664964/TVssjU7Z
- Account Management (API token) — https://gridpane.com/knowledgebase/account-management/

See `references/endpoints.md`. Last verified: 2026-10-07
