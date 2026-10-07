# Logs: which one answers which question

Full verified locations are in `gridpane-core/references/paths.md`. This file
maps a question to a log and gives the one-liners that pull the answer out.

Log lines here assume the standard Nginx combined format, where field 1 is the
client IP, field 7 the request (`"GET /path HTTP/1.1"`) and field 9 the status
code. Confirm the field layout with `head -1` on a real log before trusting a
count.

## Question → log

| Question | Log |
|---|---|
| What did PHP/Nginx just error on? | `/var/log/nginx/{site.url}.error.log` (or `/var/log/ols/{site.url}.error.log`) |
| Who is hitting the site, and what 5xx are returned? | `/var/log/nginx/{site.url}.access.log` |
| Which PHP requests are slow? | `/var/log/{site.url}{ver}.log.slow` (Nginx only) |
| Which queries are slow? | `/var/log/mysql/slow.log` |
| Why did PHP-FPM restart, or hit max children? | `/var/log/php/{php.version}/fpm.log` |
| What is failing the database? | `/var/log/mysql/error.log` |
| What did Monit restart, and when? | `/var/log/monit.log` |
| Who is being brute-forced / banned? | `/var/log/fail2ban.log`, `/var/log/php/auth.log` |
| Did GridPane change something? | `/var/log/gridpane.log`, `/var/www/{site.url}/logs/gridpane-general.log` |
| Why did an SSL provision fail? | `/var/www/{site.url}/logs/ssl-provision.log` |
| What did a WAF block? | `/var/www/{site.url}/logs/7g.log` (or `6g.log`); ModSec in the site error log |
| Why did a staging push fail? | `/var/www/{site.url}/logs/staging.log` |

## One-liners

Set the site once, then reuse it:

```bash
# [READ] Set a working variable for the rest of the session.
SITE=example.com
```

Top client IPs today (whole server):

```bash
# [READ] Top 50 client IPs across all Nginx access logs.
awk '{print $1}' /var/log/nginx/*access.log | sort | uniq -c | sort -nr | head -n 50
```

Top requested URIs on one site:

```bash
# [READ] Top 20 requested paths for one site.
awk '{print $7}' /var/log/nginx/"$SITE".access.log | sort | uniq -c | sort -nr | head -n 20
```

5xx responses for one site (which paths are failing):

```bash
# [READ] Requests returning 5xx, grouped by path.
awk '$9 ~ /^5/ {print $9, $7}' /var/log/nginx/"$SITE".access.log | sort | uniq -c | sort -nr | head -n 20
```

Count 5xx per site across the server:

```bash
# [READ] 5xx counts per access log file (per site).
for f in /var/log/nginx/*access.log; do
  n=$(awk '$9 ~ /^5/' "$f" | wc -l)
  printf '%s %s\n' "$n" "$f"
done | sort -nr
```

Hits against common attack targets, to find brute force:

```bash
# [READ] IPs hammering xmlrpc.php.
awk '$7 ~ /xmlrpc/ {print $1}' /var/log/nginx/*access.log | sort | uniq -c | sort -nr | head -n 20
```

```bash
# [READ] IPs hammering wp-login.php.
awk '$7 ~ /wp-login/ {print $1}' /var/log/nginx/*access.log | sort | uniq -c | sort -nr | head -n 20
```

Top user agents (spot bots and scrapers):

```bash
# [READ] Top 20 user agents seen by one site.
awk -F'"' '{print $6}' /var/log/nginx/"$SITE".access.log | sort | uniq -c | sort -nr | head -n 20
```

Follow a log live while reproducing a fault:

```bash
# [READ] Tail the site error log in real time.
tail -f /var/log/nginx/"$SITE".error.log
```

## OLS equivalents

On OpenLiteSpeed, swap the log paths:

```bash
# [READ] Top client IPs on an OLS server.
awk '{print $1}' /var/log/ols/*access.log | sort | uniq -c | sort -nr | head -n 50
```

OLS 503s are usually explained by the web server's own logs:

```bash
# [READ] OLS errors around 503s.
grep oops /usr/local/lsws/logs/error.log
tail -n 100 /usr/local/lsws/logs/stderr.log
```

## Gotchas

- **Rotated logs.** Access/error logs are rotated; today's file may be
  `*.access.log.1` or `.gz`. Widen the glob if counts look low.
- **Field positions differ if a custom log format is set.** Verify first.
- **Cloudflare in front.** Without real-IP restoration, `$1` is a Cloudflare IP,
  not the visitor. See `gridpane-security`.
- **ModSecurity logs to the error log**, not a separate WAF log, on Nginx.

## Sources

- GridPane Logs — https://gridpane.com/kb/gridpane-logs-how-to-find-them-and-when-to-use-them/
- Useful Commands for Managing GridPane Servers — https://gridpane.com/kb/useful-commands-for-managing-gridpane-servers/
