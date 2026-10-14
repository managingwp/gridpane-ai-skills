# /root/gridenv — GridPane server state files

GridPane stores its server-level configuration state as small `key:value` files
under `/root/gridenv`. Reading them answers configuration and state questions
directly, instead of guessing from managed config files that `gp` regenerates.

This directory is **read-only for you**: GridPane writes it, and it holds
credentials. Never edit it, never delete it, and never print secret values into a
transcript, ticket or commit.

Read this reference when you need to know *what this server is* — which web
server, which PHP versions, which cache backends, which sites, which Monit
thresholds. For per-site cache state, pair it with
`gridpane-wordpress/references/caching.md`.

## Reading it (all [READ])

```bash
# [READ] List the environment files and their sizes.
ls -la /root/gridenv
```

```bash
# [READ] The sites GridPane considers active on this server, one per line.
cat /root/gridenv/active-sites.env
```

```bash
# [READ] One non-secret key, without dumping the whole file.
grep '^server-version:' /root/gridenv/promethean.env
grep '^webserver:'      /root/gridenv/promethean.env
```

Only `grep` for the exact non-secret key you need. Do **not** `cat
/root/gridenv/promethean.env`, `cat /root/gridenv/relay.key` or `cat
/root/gridenv/backups.token` in a shared session.

## File inventory

| File | Holds | Notes |
|---|---|---|
| `active-sites.env` | The server's active site list | One `:domain:` per line, e.g. `:example.com:`. The colon-delimited form is how GridPane stores the list. |
| `promethean.env` | Server build/version and feature flags | Mixed flags and **secrets**. Grep individual keys only. |
| `nginx.env` | Nginx/stack tuning and compiled-module availability | See `nginx.env` keys below. |
| `php{VERSION}.env` | Per-PHP-version FPM/OPcache settings | One file per installed version, e.g. `php8.1.env`, `php8.5.env`. |
| `mysql.env` | MySQL/MariaDB tuning | Keys mirror server variables. |
| `redis.env` | Base Redis tuning | Present on current stacks **even when Redis is split**; do not read its presence as "single Redis". |
| `redis-page.env` | Redis **page** cache service tuning | Present when the `redis-page` service exists. |
| `redis-object.env` | Redis **object** cache service tuning | Present when the `redis-object` service exists. |
| `monit.env` | Monit warning/restart thresholds | One key per service and metric. |
| `backups.system` | Backup engine name | e.g. a single engine identifier. |
| `backups.token` | Backup secret | **Secret. Never print.** |
| `relay.key` | GridPane Relay key | **Secret. Never print.** |
| `sys-upgrades.env` | `unattended-upgrades` settings | Reboot time/window and step mode. |
| `acme-wildcard-configs/` | ACME wildcard-SSL account and cert state | Per-domain directories with private keys, account keys and `acme.sh.log`. **Treat the whole tree as secret**; never read, copy or exfiltrate it. |

The ACME tree follows
`/root/gridenv/acme-wildcard-configs/{site.url}/{site.url}_ecc/`, with a
`staging/{site.url}/` variant for the Let's Encrypt staging CA. GridPane and
`gpocsp` read it; you should only note that it exists.

## Key reference

### `promethean.env`

Server identity and installed features. Safe keys to read:

| Group | Keys (examples) |
|---|---|
| Identity/build | `server-version`, `server-build`, `webserver`, `hostname`, `system-timezone`, `cpu-cores`, `system-ram-mb`, `system-disk-gb` |
| Web server | `nginx`, `nginx-version`, `nginx-optim`, `nginx-tool`, `certbot`, `le-acme` |
| PHP | `php-ver`, `php-vX.Y:true` per version, `phpX.Y-optim`, `php-tool` |
| Database | `mysql`, `mysql-version`, `mysql-optim`, `percona-toolkit`, `mysql-tuner`, `mysql-tools` |
| Cache | `redis-server`, `redis-optim`, `redis-page`, `redis-object` |
| Plugins | `gridpane-nginx-cache-purger-plugin`, `gridpane-mailer-plugin`, `gridpane-disable-xmlrpc-plugin`, `gridpane-ultimo-plugin`, and other `gridpane-*-plugin` flags |
| Monit | `monit` plus per-service `monit-*` flags |
| Backups | `backups-version`, `backups-prune-hour`, `backups-prune-minute` |
| Versions | `nginx-version`, `configs-version`, `scripts-version`, `wpcli` |
| Admin URLs | `gp-url`, `monit-url`, `phpma-url`, `subdomain`, `source-env-managed-domain` |

**Secret keys in this file — never echo:** `gridpane-token`, `backups-token`,
`user`, `mail`, `pass`, `mysql-root`, `mysql-admin`, `phpma-user`,
`phpma-app-pass`, `http-auth-user`, `http-auth-pass`. Several are base64-encoded
but are **not** anonymised by encoding — treat them as plaintext secrets.

### `nginx.env`

Nginx tuning and compiled-module availability. Representative keys:

- Timeouts/buffers: `client_body_timeout`, `client_header_timeout`,
  `fastcgi_read_timeout`, `proxy_read_timeout`, `keepalive_timeout`,
  `send_timeout`, `reset_timedout_connection`.
- Buffers: `client_body_buffer_size`, `fastcgi_buffer_size`, `fastcgi_buffers`,
  `proxy_buffer_size`, `proxy_buffers`, `large_client_header_buffers`.
- Cache (server-wide): `fastcgi_cache_size` / `proxy_cache_size` (max cache zone
  size in MB — their presence means the FastCGI / reverse-proxy cache is
  configured server-wide), `fastcgi_cache_background_update`,
  `fastcgi_cache_revalidate`, `proxy_cache_background_update`,
  `proxy_cache_revalidate`. `fastcgi_buffering` / `proxy_buffering` are response
  buffering, not the cache itself.
- Rate limiting: `limit_req_zone_one_rate`, `limit_req_zone_one_size`,
  `limit_req_zone_wp_rate`, `limit_req_zone_wp_size`.
- Modules: `geoip-module`, `modsec-module`, `img-filter-module`,
  `lua-nginx-module-*`, `njs-nginx-module-*`, `http-v3-module`.
- `nginoil:true|false` is added here when Nginx syntax auto-repair is enabled.

Values are unit-less in the file (GridPane interprets them); do not assume a
unit. `*-module:disabled` means compiled but off, not absent.

### `php{VERSION}.env`

Per PHP version:

| Key | Meaning |
|---|---|
| `pm`, `pm.max_children`, `pm.start_servers`, `pm.min_spare_servers`, `pm.max_spare_servers`, `pm.max_requests` | PHP-FPM pool sizing per version |
| `memory_limit`, `max_execution_time`, `max_input_vars`, `max_file_uploads`, `post_max_size`, `upload_max_filesize` | PHP limits |
| `opcache.enable`, `opcache.enable_cli`, `opcache.memory_consumption`, `opcache.max_accelerated_files`, `opcache.revalidate_freq` | OPcache |

`opcache.revalidate_freq` explains why a PHP file edit can take effect up to that
many seconds later.

### `mysql.env`

Representative keys: `max_connections`, `innodb_buffer_pool_size`,
`innodb_buffer_pool_instances`, `innodb_flush_log_at_trx_commit`,
`innodb_flush_method`, `innodb_io_capacity`, `innodb_io_capacity_max`,
`innodb_redo_log_capacity`, `connect_timeout`, `slow_query_log`,
`long_query_time`, `disable_log_bin`, `binlog_expire_logs_seconds`,
`thread_pool_size`, `thread_handling`. Note this file mixes `key:value` and
`key = value` (spaces around `=`) lines.

### `redis*.env`

`maxmemory`, `maxmemory-policy`, `maxmemory-samples` and (for the object cache)
`default-pass` (**secret — never print**, even though the TLS/ACL password is
what it is). `redis.env` applies to the single-Redis layout; `redis-page.env` and
`redis-object.env` apply to the split layout.

### `monit.env`

Thresholds named `{service}-{cpu|mem}-{warning|restart}-{threshold-percent|cycles|threshold-mb}`.
Examples of service prefixes: `nginx`, `mysql`, `redis`, `redis-page`,
`redis-object`, `php8.0` … `php8.5`, `php74`. Use these to interpret what Monit
considers "high" on this specific server rather than assuming a fleet default.

### `sys-upgrades.env`

`Unattended-Upgrade-Automatic-Reboot`, `Unattended-Upgrade-Automatic-Reboot-time`,
`Unattended-Upgrade-MinimalSteps`, `Unattended-Upgrade-SyslogEnable`.

## Using it for diagnosis

- **Which sites exist here?** `active-sites.env`. Use it to enumerate sites
  without the panel or API, and to confirm a site's presence before acting.
- **Which cache backends are configured?** Presence of `redis-page.env` and/or
  `redis-object.env`, plus `redis-page:true` / `redis-object:true` in
  `promethean.env`, and the `fastcgi_cache_*` / `proxy_cache_*` keys in
  `nginx.env` (server-wide cache machinery and tuning). This is **server-level**;
  it does not prove a *given site* uses that backend. Confirm the per-site method
  as described in `gridpane-wordpress/references/caching.md`.
- **Worked example (2026-10-09 capture):** `promethean.env` had `redis-page:true`
  and `redis-object:true`, `nginx.env` had both `fastcgi_cache_size` and
  `proxy_cache_size`, and `monit.env` tracked `redis`, `redis-page` and
  `redis-object`. That is a split-Redis server: its page-cached sites answer with
  `X-Grid-SRCache-Fetch`, **not** `X-Grid-Cache`. Reading only `X-Grid-Cache`
  would wrongly call such a site "uncached".
- **Which PHP versions are installed / defaulted?** `php{VERSION}.env` filenames
  and `php-ver` in `promethean.env`.
- **How is this server built?** `server-version`, `server-build`,
  `nginx-version`, `configs-version`, `scripts-version` in `promethean.env`.
- **What are this server's Monit thresholds?** `monit.env`, which beats a
  generic threshold in a diagnosis.
- **Single vs split Redis:** use the **`promethean.env` flags** (`redis-page`,
  `redis-object`) and the **service prefixes in `monit.env`** (`redis-page-*`,
  `redis-object-*`) to decide. Do **not** use `redis.env` presence: on a real
  capture (2026-10-09) `redis.env`, `redis-page.env` and `redis-object.env` all
  coexisted, with `redis-server:true` alongside `redis-page:true` and
  `redis-object:true`, and Monit tracking all three services. The split is the
  reliable signal; the `redis.env` file can remain as base/legacy tuning.

## Gotchas

- **Treat the directory as immutable and read-only.** GridPane rewrites it and
  reportedly marks it write-protected; editing or deleting files is not a
  supported operation.
- **It contains live credentials.** Anonymise before sharing: redact every key
  listed as a secret above, all `acme-wildcard-configs/` contents, and the
  managed subdomain/hostname. Real domains in `active-sites.env` are client data;
  replace them with `example.com`-style names.
- **Values have no units.** `innodb_buffer_pool_size:2709`, `maxmemory:812mb`,
  and Nginx buffer values are interpreted by GridPane. Read the KB page for the
  key before converting.
- **Two syntaxes coexist.** Most files are `key:value`; `mysql.env` uses `key =
  value` for some entries. Split on the first `:` or `=` as appropriate, and
  trim spaces.
- **`active-sites.env` is colon-delimited**, e.g. `:example.com:`, not a plain
  list.

## Unverified

- Whether `/root/gridenv` is always `chattr +i` (write-protected), and how that
  behaves on every Ubuntu release. Tracked in `OPEN-QUESTIONS.md`.
- The complete key set for each file: new keys appear as GridPane adds features.
  The tables here cover the keys seen in maintainer-supplied output dated
  2026-10-09 plus the keys the KB names explicitly.
- Which Redis config the split `redis-page`/`redis-object` services actually read,
  and whether the coexisting `redis.env` has any effect on them.
- The meaning of every `promethean.env` key (some, such as `gpfailsync-running`
  and `configs-update-processing`, are not documented in the KB).

## Sources

- Configure Monit with GP-CLI — https://gridpane.com/kb/configure-monit-with-gp-cli/
  (documents `/root/gridenv/monit.env`).
- Nginoil — https://gridpane.com/kb/nginoil-automatically-fix-nginx-syntax-errors/
  (documents `/root/gridenv/nginx.env`).
- Diagnosing and Fixing SSL Certificate Issues —
  https://gridpane.com/kb/diagnosing-and-fixing-ssl-certificate-issues/
  (documents `/root/gridenv/acme-wildcard-configs/`).
- Local/Remote Backups — https://gridpane.com/kb/local-remote-backups/
  (documents `/root/gridenv/backups.system` and `/root/gridenv/backups.token`).
- Configure Redis — https://gridpane.com/kb/configure-redis/
  (single vs `redis-page`/`redis-object` layouts).
- Maintainer-supplied capture of `/root/gridenv` from a real GridPane server,
  2026-10-09 (fields verified against the files; secret values redacted).

Last verified: 2026-10-09
