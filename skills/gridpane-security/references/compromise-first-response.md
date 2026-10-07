# Suspected compromise: first response

Order matters: **contain → preserve evidence → identify → clean → harden.**
Preserve logs before they rotate or are overwritten, or you lose the ability to
work out how the attacker got in. Use read-only detection. Never write or run
attack payloads.

This is first response for a GridPane site. For deeper forensic work, point the
team at dedicated hacked-site triage tooling (a structured triage workflow over
code, database dumps and access logs).

## 1. Contain

- If the site is actively serving malware or spam, suspend it rather than deleting
  anything ([WRITE]):

  ```bash
  # [WRITE] Suspend a compromised site to stop serving malicious content.
  # Blast radius: site example.com only. Rollback: `-unsuspend`.
  # Confirm before running.
  gp site example.com -suspend
  ```

- Rotate credentials from a **clean** machine: GridPane account password/2FA,
  WordPress admin passwords, database passwords, SSH keys.
- Do **not** delete suspected files yet; that is evidence.

## 2. Preserve evidence

Copy logs and the site's state aside **before** rotation/cleanup:

```bash
# [READ] Make a timestamped copy of the logs and a file listing for analysis.
ts=$(date +%Y%m%d%H%M%S)
mkdir -p /root/incident-$ts
cp -a /var/www/example.com/logs /root/incident-$ts/site-logs
cp -a /var/log/nginx/example.com.*.log /root/incident-$ts/ 2>/dev/null || true
find /var/www/example.com/htdocs -type f -newermt '-14 days' \
    -printf '%T+ %p\n' > /root/incident-$ts/recent-files.txt
```

```bash
# [READ] Snapshot what the database contains around users/options.
gp wp example.com user list --fields=ID,user_login,user_email,roles,user_registered
```

Keep these copies off the compromised filesystem if possible.

## 3. Identify (read-only)

```bash
# [READ] Who is hitting the site, and from where.
tail -n 100 /var/www/example.com/logs/7g.log
```

```bash
# [READ] Recently modified PHP files under the webroot (common in injected code).
find /var/www/example.com/htdocs -type f -name '*.php' -newermt '-14 days'
```

```bash
# [READ] WordPress integrity checks and plugin/theme status.
gp wp example.com core verify-checksums
gp wp example.com plugin list --fields=name,status,version,update
```

Look for: unexpected admin users, modified core files, unknown files in
`wp-content/uploads`, injected `eval`/`base64` code, unfamiliar cron events, and
odd outbound requests in the PHP slow log (`curl_exec`).

## 4. Clean

Only after evidence is preserved:

- Reinstall WordPress core (`gp wp example.com core download --force`) and
  reinstall/update vulnerable plugins and themes.
- Remove confirmed malicious files and unauthorised users.
- Replace `wp-config.php` salts/keys and reset all admin passwords.
- Rebuild the database from a known-good backup if you cannot be sure it is
  clean.

This step is [WRITE]/[DESTRUCTIVE] territory: get explicit confirmation, and
verify backups exist before overwriting anything.

## 5. Harden

- Ensure the 7G WAF is on and rulesets are appropriate (`references/waf.md`).
- Ensure Fail2ban jails are active; consider the Cloudflare action
  (`references/fail2ban.md`).
- Turn on automatic updates for the affected plugins, or schedule them.
- Review `references/cloudflare.md` for origin lockdown.
- Consider a malware scan (Maldet/ClamAV) and a vulnerability scan.

## Gotchas

- **Deleting files or clearing logs first destroys the evidence** of the initial
  access vector. Preserve first.
- **Suspending is reversible; deleting is not.** Prefer suspend while you work.
- **A clean front-end does not mean clean.** Check the database and uploads, not
  just theme files.
- **Do not reuse still-compromised credentials.** Rotate from a clean machine.

## Unverified

- Whether Maldet/ClamAV and the GridPane vulnerability scanner are installed by
  default or must be added. Confirm on the server.

## Sources

- Introduction to Maldet and ClamAV — https://gridpane.com/kb/an-introduction-to-maldet-and-clamav-malware-scanning/
- WordPress Vulnerability Scanning and Notifications — https://gridpane.com/kb/wordpress-vulnerability-scanning-and-notifications/
- Default GridPane Security and Additional Options — https://gridpane.com/kb/default-gridpane-security-and-additional-options/
- Server Provider Attack Warnings — https://gridpane.com/kb/server-provider-attack-warnings/
