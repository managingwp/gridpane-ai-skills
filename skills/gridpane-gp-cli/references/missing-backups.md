# Missing backups after site deletion or recreation

Use this evidence-first runbook when a deleted/recreated site has no backups in
the panel. Discovery only: a listed revision is a recovery candidate, not proof
that its chunks, database dump and files can be restored successfully.

## 1. Preserve the evidence

Record the original and recreated site IDs, deletion time (with timezone), server
UUID, domain history, remote configuration reference, region and bucket. A new
site ID or system user does not by itself explain missing backups. Current
preferences describe the recreated site's storage, which may differ from the
original destination. Compare the creation and storage-change history.

Keep raw logs private. Redact application/server tokens, storage credentials,
keyrings and the entire encoded argument after `-enable-remote-backups`:
Base64 is encoding, not encryption. Preserve the original destination while
investigating; storage re-adds, initialization, new backups and purges are not
discovery steps.

## 2. Establish whether a backup completed

Read the central logs with context, including rotated files where available.
The next line after a domain match may contain the actual outcome:

```bash
# [READ] Log availability and enabled-state outcomes; inspect locally before sharing.
ls -lh /opt/gridpane/backup.log* /opt/gridpane/active.backups.monitoring.log*
grep -nF -A 1 'Checking if backups are enabled for example.com' /opt/gridpane/backup.log
grep -nF 'example.com' /opt/gridpane/backup.log
```

- `will be backed up to`, `Repository set to` and repository initialization
  describe configuration, not a completed revision.
- `No backups are enabled.` establishes the state at that check. Repeated
  historical checks can establish repeated disabled state, not that a manual
  backup never existed elsewhere or why setup failed.
- An available-backups payload such as `"automatic":" ","manual":""`
  reports an empty discovery result for that queried source. It is not a
  completed backup or proof of global absence.
- Generic server safety-backup completion messages do not establish a complete
  website files-and-database backup. Missing per-site logs after deletion and
  an empty current monitoring log do not establish that older jobs never ran.

Use the completion signatures and log paths in [backups.md](backups.md).

## 3. Identify the storage-specific snapshot ID

Run Duplicacy from an existing initialized site directory. `Repository has not
been initialized` from `/root` is a working-directory error, not evidence that
backup storage is empty. Read installed help; the observed 2.7.2 build prints
its version in general help and rejects `-version`.

```bash
# [READ] Existing repository context and installed CLI syntax.
cd /var/www/example.com || exit
duplicacy help
duplicacy help list
```

Inspect only selected preference fields; `.duplicacy` may be a directory or a
file pointing to the preference directory. This Bash/jq example handles both:

```bash
# [READ] Selected fields only; strip URL userinfo/query/fragment before display.
(
  cd /var/www/example.com || exit
  pref_dir=.duplicacy
  if [[ -f "$pref_dir" ]]; then
    pref_dir=$(cat -- "$pref_dir") || exit
  fi
  jq 'map({name, id, encrypted, storage: (.storage |
    sub("://[^/@]*@"; "://") | split("?")[0] | split("#")[0])})' \
    "$pref_dir/preferences"
)
```

Review even this selected output before sharing; storage paths can identify
accounts. Never dump `keys`, keyrings or the full preferences into a ticket.

Use the `id` belonging to the selected storage, not a guessed domain or the
local ID. One observed configuration used local `gridpane-<uuid>-example-com`
but remote `example-com`. Recreation retained the local ID on that server;
neither ID pattern nor preservation is a universal guarantee.

## 4. Query existing storage, then alternate IDs

Duplicacy `list` reads remote backup data but can write local cache/keyring
state. Under the existing safety protocol, classify it as [WRITE]: explain the
local effect, obtain confirmation and preserve the site's `.duplicacy` state
(including the resolved directory if it is a pointer file) before running it.
Rollback: restore that preserved local state only if needed and no job is using
it. No remote snapshot change is intended. `-no-script` disables pre/post hooks.

```bash
# [WRITE] Local metadata effects only, as described above; confirm and preserve first.
# Replace the directory/storage with verified values; omit -id to use that storage's ID.
(
  cd /var/www/example.com || exit
  duplicacy -no-script list -storage wasabi
  result=$?
  printf 'Duplicacy exit status: %s\n' "$result"
  exit "$result"
)
```

Wait for the prompt to return. `Storage set to ...` alone is not completion.
An exit of 0 with no revision lines means none were listed for that ID in that
destination; a nonzero exit or credential prompt leaves discovery inconclusive.
Stop at unknown credentials rather than changing passwords. A CLI credential
failure may mean the GridPane wrapper supplies credentials differently.

After a successful empty targeted listing, use `duplicacy -no-script list
-storage wasabi -all` under the same [WRITE] safeguards to inspect alternate IDs.
Keep the full output initially, including errors. If filtering later, use
`pipefail` and retain non-snapshot messages; a successful filter is not proof
that the upstream listing succeeded. Listing metadata does not verify chunks.

## 5. Check original destinations and stop at the coverage boundary

Compare credential-free endpoint/bucket summaries from other existing site
preferences. Deduplicate by region, endpoint and bucket/path, not region alone.
Use an existing site that already accesses the intended bucket and pass the
target's verified remote `-id`; omitting `-id` there lists the other site's
backups. This requires the same local-state safeguards as above. Avoid guessing
the original bucket or changing the current URL's region in place.

Track each checked destination, ID scope, exit status and revision dates. A
successful all-ID listing without a match closes only that destination and
searched names. Other sites' revisions prove metadata is accessible there, not
that the missing site was backed up or that those revisions are restorable.

When identified sources are exhausted, report **no matching revision found in
the checked sources**, not **no backup ever existed**. Ask GridPane support to
trace the original configuration reference to its exact bucket and explain any
creation-request/disabled-state discrepancy. Prioritize provider snapshots from
before deletion, recovered onto a separate server, plus migration exports and
previous domain/source copies. Stop repeating empty listings; do not restore
over a shared server or initialize/prune storage as an experiment.

## Unverified

The cause of remote backup setup being requested at creation while subsequent
checks report no backups enabled remains unknown. An empty listing does not
identify the original bucket, prove deletion purged backups, or explain that
setup failure. Obtain the original destination mapping and setup outcome from
GridPane support before asserting a root cause.

Last verified: 2026-10-23 from maintainer-supplied GridPane logs, sanitized
preferences and Duplicacy 2.7.2 help/list output. See
`gridpane-core/references/sources.md` for the evidence scope.
