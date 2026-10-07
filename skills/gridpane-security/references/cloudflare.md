# Cloudflare with GridPane

What changes when a GridPane site sits behind Cloudflare's proxy.

## Real visitor IPs at the origin

Behind the proxy, the origin initially sees Cloudflare IPs. GridPane's stack
automatically translates the real visitor IP coming through Cloudflare, so
Fail2ban, access logs and rate limiting act on the real client address.

Verify that logs show the visitor IP rather than a Cloudflare IP:

```bash
# [READ] Top client IPs; these should be real visitors, not 172.64.x / 104.x.
awk '{print $1}' /var/log/nginx/example.com.access.log | sort | uniq -c | sort -nr | head
```

If you must refresh the trusted Cloudflare ranges, GridPane provides a documented
procedure ("Updating Cloudflare Real IPs") rather than hand-editing Nginx.

## SSL mode

Set Cloudflare's SSL/TLS mode to **Full (strict)**. A permissive mode such as
Flexible causes the classic redirect loop: Cloudflare talks HTTP to the origin,
the origin redirects to HTTPS, Cloudflare speaks HTTP again, and so on. See
`gridpane-incident-triage` for the redirect-loop triage.

Certificate options at the origin:

- **Let's Encrypt** via GridPane (often webroot or DNS-API challenge).
- **Cloudflare Origin certificate** installed on the origin.

Either works with Full (strict); keep the origin certificate valid or the edge
will refuse the origin connection.

## Caching interplay

Cloudflare has its own cache. When diagnosing "my change didn't show", there are
now two caches to consider: the server page cache (`X-Grid-Cache`) and
Cloudflare's edge cache. Purge both. GridPane has a documented Cloudflare caching
article; the Cloudflare APO feature also interacts with page caching.

## Locking the origin to Cloudflare IPs

Restricting the origin firewall so it only accepts traffic from Cloudflare IP
ranges prevents attackers from bypassing Cloudflare and hitting the origin
directly. Risks:

- If the Cloudflare range list is stale, or the site must be reachable directly
  (e.g. health checks, staging, a monitoring probe), you can lock out legitimate
  traffic.
- DNS-only (grey cloud) records, direct IP access and mail/other services on the
  same host are not covered by Cloudflare ranges and can break.

Do this only with a current Cloudflare IP list and a tested rollback (a second
access path or the ability to edit the firewall from console). Prefer Cloudflare
**Authenticated Origin Pulls** where it fits.

## Gotchas

- **Bans at the origin do not stop proxied attackers.** Ban at Cloudflare (see
  `references/fail2ban.md`).
- **Two caches.** Never conclude a server change failed until Cloudflare's cache
  is also cleared.
- **Redirect loops are usually an SSL-mode problem**, not WordPress.
- **Real-IP translation can be undone** by a custom Nginx config that reads the
  socket address instead of the forwarded header.

## Unverified

- The exact mechanism/header GridPane uses for real-IP restoration (a documented
  `set_real_ip_from`/`real_ip_header` include, or a Cloudflare-specific config).
  Confirm on the server before editing any real-IP config.
- The current Cloudflare APO interaction with GridPane page caching. Confirm from
  the Cloudflare APO KB article before advising.

## Sources

- Using Cloudflare with GridPane — https://gridpane.com/kb/using-cloudflare-with-gridpane/
- Updating Cloudflare Real IPs — https://gridpane.com/kb/updating-cloudflare-real-ips/
- Cloudflare Caching and GridPane — https://gridpane.com/kb/cloudflare-caching-and-gridpane/
- Using Fail2Ban with Cloudflare — https://gridpane.com/kb/using-fail2ban-with-cloudflare/
- Website Redirecting When Cloudflare's Proxy Active — https://gridpane.com/kb/website-redirecting-when-cloudflares-proxy-active/
- How to Set Up Cloudflare APO — https://gridpane.com/kb/how-to-set-up-cloudflare-apo/
