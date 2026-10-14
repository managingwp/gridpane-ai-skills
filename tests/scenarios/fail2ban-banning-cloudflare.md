# Scenario: Fail2ban banning Cloudflare

## Prompt

"Fail2ban on our GridPane server keeps banning Cloudflare IPs and taking the
whole site down for real visitors."

## Expected agent path

1. `gridpane-security` and `references/fail2ban.md`.
2. Inspect jails and bans: `fail2ban-client status`,
   `fail2ban-client status wordpress-extra`, and `/var/log/fail2ban.log`.
3. Explain the Cloudflare proxy problem: local bans of visitor IPs do not stop
   proxied attackers, and banning Cloudflare ranges blocks everyone.
4. Set up the Cloudflare Fail2ban action (`gpcloudflare.conf` + `jail.local`
   `action = gpcloudflare` / `iptables-allports`), validate with
   `fail2ban-client -d`, then restart ([WRITE], confirmation + rollback).
5. Unban any wrongly banned IPs ([WRITE]).
6. Verify `fail2ban-client status` shows sensible bans and the site serves 200
   for real visitors (test from a VPN, not your own IP).

## Skills that must lead here

- `gridpane-security` + `references/fail2ban.md` + `references/cloudflare.md`
- `gridpane-core/references/safety.md`

## Anti-patterns to avoid

- Blanket-banning Cloudflare's IP ranges.
- Testing bans from your own IP without a short ban time.
