# Migrately – A CLI Tool for Full Server to Server Cloning

- Status: changed
- Interval: 2026-10-21 → 2026-11-06
- Article: https://gridpane.com/kb/migrately
- Cited by: not recorded for this backfilled interval
- Extracted text, not the published HTML: code blocks and tables may reflow.

## Diff

```diff
--- 2026-10-21
+++ 2026-11-06
@@ -1,6 +1,6 @@
-Information
+Important: migrating from Ubuntu 18.04 or 20.04
 
-This tool moves everything on a server — every site's files, database, and configuration — to a new, empty destination server. Treat the destination as disposable: anything already there will be overwritten. Don't run this against a server that has data you want to keep.
+Migrately is currently designed for servers on our supported stacks: Ubuntu 22.04, 24.04 and 26.04. If your source server runs Ubuntu 18.04 or 20.04 (an unsupported stack), its Redis setup differs from the new server's. Sites that have Redis page caching or Redis object caching switched on will not have working caches after migration unless you follow the steps in "Migrating from an older server (18.04 / 20.04)" below.
 
 Table of Contents
 - Introduction
@@ -12,8 +12,15 @@
 - Optional: Matching Your Backup Settings
 - If a Site Gets Skipped
 - Step 5: Wrapping Up
+- Migrating from 18.04 and 20.04:
+– Migrating From an Older Server (18.04 / 20.04)
+– Already Migrated from 18.04 / 20.04 with Redis Caching On?
 - Troubleshooting
 
+Information
+
+This tool moves everything on a server — every site's files, database, and configuration — to a new, empty destination server. Treat the destination as disposable: anything already there will be overwritten. Don't run this against a server that has data you want to keep.
+
 Introduction
 Migrately is our custom-built CLI tool that our own support team uses to move WordPress sites on our fully managed service from one server to a brand-new one. This is now available to everyone using GridPane.
 What it does
@@ -35,6 +42,7 @@
 Step 3. Connect to your server by SSH as Root user (we like and use Termius)
 
 Server Requirements
+The destination server must be on a supported stack (Ubuntu 22.04, 24.04 or 26.04). If the source server is on Ubuntu 18.04 or 20.04, follow “Migrating from an older server” first.
 You’ll need the following to begin using Migrately:
 - Two GridPane servers – your old one (the source) and a brand-new, empty one (the destination).
 - Both servers need to use the same server stack (both Nginx or both OpenLiteSpeed), and same database engine (both Percona, or both MariaDB) – you can check this in your GridPane dashboard if you’re unsure.
@@ -254,5 +262,91 @@
 
 Run unattended jobs inside screen or tmux. The exit-status behavior is the same either way, but a dropped terminal won't kill the job.
 
+Migrating From an Older Server (18.04 / 20.04)
+In short: switch Redis caching off, run Migrately without option 3, make two wp-config.php edits on the new server, then switch caching back on.
+
+Step A. Before you migrate (source server, in the GridPane app)
+- For every site you’re migrating, switch Redis page caching to FastCGI (or off). FastCGI keeps your sites cached during the move and doesn’t use Redis.
+- For every site, switch Redis object caching off. If the site uses Object Cache Pro, switch that off too.
+- Check that Object Cache Pro is really off. On the source server, this should print nothing:
+
+ls /var/www/*/object-cache-pro-configs.php 2>/dev/null
+If it lists a site, switch Object Cache Pro off for that site in the app again before continuing.
+Step B. Delete the object-cache.php file
+After disabling Redis caching, you can make sure this file is deleted for each website on your origin server with the following command:
+for f in /var/www/*/htdocs/wp-content/object-cache.php; do { [ -e "$f" ] || [ -L "$f" ]; } || continue; rm -fv "$f"; done
+This will loop through each site and remove this specific file.
+If you see any errors listed after step 14, you can also run this command on the destination server before turning any Redis page or object caching back on.
+Step C. Run Migrately, but skip option 3
+- Manual run: start at option 4 and work through to 10. Do not run option 3 (Redis migration).
+- Single-command run: use the same command as the normal guide, but leave out the 3 so the sequence runs 4 → 10, then 14.
+
+On an older server, option 3 would copy its old Redis settings onto the new server. The new server doesn’t need them.
+Step D. After migrating (destination server, as root)
+Run this once. It updates every migrated site’s wp-config.php for the new server’s Redis setup. It is safe to run more than once, and it doesn’t change sites that are already set up for the new server.
+for f in /var/www/*/wp-config.php; do
+# Object cache: point at the new object-cache Redis socket
+sed -i 's|/var/run/redis/redis-server.sock|/var/run/redis-object/redis-object.sock|g' "$f"
+# Nginx Helper: add the username/password lines the new page-cache Redis needs
+# (GridPane fills in the real values when you switch Redis page caching on)
+if grep -q "RT_WP_NGINX_HELPER_REDIS_PREFIX" "$f" && ! grep -q "RT_WP_NGINX_HELPER_REDIS_USERNAME" "$f"; then
+sed -i "/RT_WP_NGINX_HELPER_REDIS_PREFIX/a //define('RT_WP_NGINX_HELPER_REDIS_PASSWORD', '');" "$f"
+sed -i "/RT_WP_NGINX_HELPER_REDIS_PREFIX/a //define('RT_WP_NGINX_HELPER_REDIS_USERNAME', '');" "$f"
+fi
+done
+Then, in the GridPane app on the new server, switch caching back on for each site: Redis page caching, and Redis object caching or Object Cache Pro. Switching them on sets each site’s Redis username, password and database for the new server.
+Custom Nginx overrides: if you had a custom Redis cache file on the old server (/etc/nginx/common/_custom/<site>-wp-redis.conf), it was copied across as it was and still contains the old Redis settings. Review it, or remove it, before you switch Redis page caching on.
+Step E. Check it worked (destination server)
+Object cache: should show “Status: Connected”:
+gp wp {site} redis status
+E.g:
+gp wp example.com redis status
+Page cache: the second request should show “x-grid-srcache-fetch: HIT””
+curl -sI https://{site}/ | grep -i x-grid-srcache-fetch
+curl -sI https://{site}/ | grep -i x-grid-srcache-fetch
+Run these before you point DNS at the new server. Until then, use a local hosts file entry, or replace the curl commands with:
+curl -sI --resolve {site}:443:{new-server-ip} https://{site}/.
+
+Already Migrated from 18.04 / 20.04 with Redis Caching On?
+If you already migrated from an 18.04 / 20.04 server with Redis caching switched on, nothing is lost. Your sites still point at the old single Redis, which doesn’t run on the new server. These steps switch caching off, repair wp-config.php, then switch caching back on so GridPane rebuilds each site’s Redis settings for the new server.
+1. Check Redis is running (destination server, as root)
+systemctl is-active redis-object redis-page
+Both lines should say active. If either doesn’t, stop here and contact support.
+2. Switch caching off (GridPane app, new server)
+For each affected site:
+- Switch page caching from Redis to FastCGI (or off).
+- Switch Redis object caching off. If the site uses Object Cache Pro, switch that off too.
+
+This step must come first. A site that is already set to Redis page caching doesn’t get its Nginx files rebuilt if Redis is switched on again.
+3. Delete the object-cache.php file
+After disabling Redis caching, you can make sure this file is deleted for each website on your origin server with the following command:
+for f in /var/www/*/htdocs/wp-content/object-cache.php; do { [ -e "$f" ] || [ -L "$f" ]; } || continue; rm -fv "$f"; done
+This will loop through each site and remove this specific file.
+4. Repair wp-config.php (destination server, as root)
+Run the following (the same command as in Step C above):
+for f in /var/www/*/wp-config.php; do
+# Object cache: point at the new object-cache Redis socket
+sed -i 's|/var/run/redis/redis-server.sock|/var/run/redis-object/redis-object.sock|g' "$f"
+# Nginx Helper: add the username/password lines the new page-cache Redis needs
+# (GridPane fills in the real values when you switch Redis page caching on)
+if grep -q "RT_WP_NGINX_HELPER_REDIS_PREFIX" "$f" && ! grep -q "RT_WP_NGINX_HELPER_REDIS_USERNAME" "$f"; then
+sed -i "/RT_WP_NGINX_HELPER_REDIS_PREFIX/a //define('RT_WP_NGINX_HELPER_REDIS_PASSWORD', '');" "$f"
+sed -i "/RT_WP_NGINX_HELPER_REDIS_PREFIX/a //define('RT_WP_NGINX_HELPER_REDIS_USERNAME', '');" "$f"
+fi
+done
+It points each site’s object cache at the new server’s Redis and adds the page-cache username and password lines.
+Custom Nginx overrides: review or remove any /etc/nginx/common/_custom/{site}-wp-redis.conf copied from the old server before the next step.
+5. Switch caching back on (GridPane app, new server)
+For each site, switch page caching to Redis, and switch on Redis object caching or Object Cache Pro (whichever the site used before). This rebuilds each site’s Nginx cache files and Redis login for the new server.
+6. Check it worked (destination server)
+No Nginx cache file should still point at the old Redis — should print nothing:
+grep -lE 'redis2?_pass redis;' /etc/nginx/common/*.conf /etc/nginx/common/_custom/*.conf 2>/dev/null
+Object cache: should show “Status: Connected”:
+gp wp {site} redis status
+Page cache: the second request should show “x-grid-srcache-fetch: HIT”:
+curl -sI https://{site}/ | grep -i x-grid-srcache-fetch
+curl -sI https://{site}/ | grep -i x-grid-srcache-fetch
+If the first command lists any files, or a site still doesn’t connect or cache, contact support with the site name.
+
 Troubleshooting
 If you run into a message you don’t recognize, or a step fails partway through, your session log will have the full details — check the terminal output, or if you used script to record your session, review that log file. You can always safely re-run any step; migrately is designed to pick up where it left off.
```
