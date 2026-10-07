# Fail2ban on GridPane

Fail2ban parses system logs, matches filters, and bans abusive IPs through
"jails" (a filter plus actions). It is installed and active by default on
GridPane servers and logs to `/var/log/fail2ban.log`.

## Status and jails

```bash
# [READ] All jails and their current ban counts.
fail2ban-client status
```

```bash
# [READ] Bans for the WordPress brute-force jail.
fail2ban-client status wordpress-extra
```

WordPress-related jails include `wordpress-wp-login`, `wordpress-xmlrpc`,
`wordpress-hard`, `wordpress-soft` and `wordpress-extra` (not all are present on
every server). The `wordpress-extra` jail's ban time is 24 hours (86400 seconds).

Logs:

- Fail2ban events: `/var/log/fail2ban.log`
- Authentication events: `/var/log/php/auth.log`

## Enable WP-aware bans

The WP fail2ban plugin feeds WordPress events to Syslog so the jails can act. The
`gp` command installs it as a must-use plugin and configures the jail:

| Label | Command |
|---|---|
| [WRITE] | `gp site {site.url} -enable-wp-fail2ban` |
| [WRITE] | `gp site {site.url} -disable-wp-fail2ban` |
| [WRITE] | `gp site {site.url} -configure-wp-fail2ban -block-user-enumeration` / `-unblock-user-enumeration` |
| [WRITE] | `gp site {site.url} -configure-wp-fail2ban -block-stupid-usernames` / `-unblock-stupid-usernames` |
| [WRITE] | `gp site {site.url} -configure-wp-fail2ban -guard-comments` / `-unguard-comments` |
| [WRITE] | `gp site {site.url} -configure-wp-fail2ban -guard-password-resets` / `-unguard-password-resets` |
| [WRITE] | `gp site {site.url} -configure-wp-fail2ban -guard-pingbacks` / `-unguard-pingbacks` |
| [WRITE] | `gp site {site.url} -configure-wp-fail2ban -guard-spam` / `-unguard-spam` |
| [WRITE] | `gp site {site.url} -configure-wp-fail2ban -default` |

## Ban and unban an IP

```bash
# [WRITE] Manually ban an IP for 24h in the WordPress jail.
# Blast radius: that jail's bans only. Rollback: unban (below).
# Confirm before running.
fail2ban-client set wordpress-extra banip 203.0.113.10
```

```bash
# [WRITE] Unban an IP (e.g. a false positive locking out a client).
# Blast radius: that jail's bans only. Confirm before running.
fail2ban-client set wordpress-extra unbanip 203.0.113.10
```

## Are you banning Cloudflare IPs?

Behind the Cloudflare **proxy** (orange cloud), the origin sees Cloudflare IPs.
GridPane automatically translates the real visitor IP, so Fail2ban bans the real
attacker. However, **banning the attacker's IP locally does not stop them** while
they remain proxied through Cloudflare: Cloudflare still forwards their traffic
to the origin.

The fix is a custom Fail2ban action that sends ban/unban requests to Cloudflare's
API, so the ban happens at the edge:

- Create `/etc/fail2ban/action.d/gpcloudflare.conf` from the Fail2ban project's
  current `cloudflare.conf`.
- Add your Cloudflare API token and account email to that file.
- In `/etc/fail2ban/jail.local`, set the action on each WordPress jail to:

  ```ini
  action = gpcloudflare
      iptables-allports
  ```

  (Use `iptables-allports`, not `iptables-multiport`.)

- Validate and reload:

  ```bash
  # [WRITE] Validate config and restart Fail2ban.
  # Blast radius: whole server's Fail2ban. Rollback: restore jail.local backup.
  # Confirm before running.
  fail2ban-client -d && service fail2ban restart
  ```

With this in place, one Cloudflare account ban applies across every origin server
configured the same way.

## Gotchas

- **Test from a VPN.** Banning your own office IP (or letting a test ban it) locks
  you out; keep ban times short while testing.
- **Cloudflare propagation delay.** There can be a short delay between Fail2ban
  banning and Cloudflare enforcing it, so the attacker may get a few extra
  attempts.
- **Do not blanket-ban Cloudflare's IP ranges.** That blocks all proxied traffic
  to your sites. Always resolve and ban the real visitor IP.
- **Editing `jail.local`/`jail.conf`** is server-wide and affects every site.

## Sources

- Configuring Fail2Ban to Prevent Brute Force Attacks — https://gridpane.com/kb/configuring-fail2ban-to-prevent-brute-force-attacks/
- Using Fail2Ban with Cloudflare — https://gridpane.com/kb/using-fail2ban-with-cloudflare/
- Useful Commands (manual ban) — https://gridpane.com/kb/useful-commands-for-managing-gridpane-servers/
