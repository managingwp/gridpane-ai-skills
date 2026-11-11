# Cloning a site to a new URL on a different server

- Status: changed
- Interval: 2026-10-21 → 2026-11-06
- Article: https://gridpane.com/kb/cloning-a-duplicate-site-with-a-new-url-to-a-different-server
- Cited by: not recorded for this backfilled interval
- Extracted text, not the published HTML: code blocks and tables may reflow.

## Diff

```diff
--- 2026-10-21
+++ 2026-11-06
@@ -1,3 +1,7 @@
+Important
+
+Prior to Ubuntu 26.04 Percona or MariaDB database options used to be interchangeable, but they no longer are. When you move, clone or restore a site, always keep it on the same database type it came from: Percona to Percona, or MariaDB to MariaDB. Moving a site between the two types is likely to fail, and support for fixing those failures is limited. If a move between types does go wrong, the fix will almost always be to redo it onto a server with the matching database type.
+
 Table of Contents
 - Introduction
 - What Settings Clone Across
@@ -6,6 +10,7 @@
 - Step 3. Configure Your URL and Clone Settings
 - Step 4. Check Your Cloned Website
 - Cloning and Staging Sites
+- Cloning from Ubuntu 20.04 to 26.04
 
 Introduction
 In your workflow there may be times when you want to clone a duplicate of a site to a new URL, for example:
@@ -141,3 +146,48 @@
 As noted in Step 3.1, you can choose to clone your staging site along with the main site if you would like to do so.
 You can also clone individual staging sites to a different URL either on the same server or a new server if you have a need to do so though. You will find the same options for cloning in your staging site’s customizer, and you can follow the same steps above like you would when cloning a production website.
 One thing you can’t do, however, is create or clone staging sites to “staging” subdomains on GridPane. For example, if you try to create the website “staging.website.com” as a regular site, it will fail and result in an error message. This will also fail in the exact same way during the cloning process.
+
+Cloning from Ubuntu 20.04 to 26.04
+There are a few additional steps that may be needed when migrating to a new 26.04 server, which requires running a few commands directly on your server. If this is your first time connecting to a server via SSH, please see the following articles to get started:
+
+Step 1. Generate your SSH Key
+Step 2. Add your SSH Key to GridPane (also see Add default SSH Keys)
+Step 3. Connect to your server by SSH as Root user (we like and use Termius)
+
+Step A. Before you migrate (source server, in the GridPane app)
+- Switch Redis page caching to FastCGI (or off) if applicable. FastCGI keeps your sites cached during the move and doesn’t use Redis.
+- Switch Redis object caching off. If the site uses Object Cache Pro, switch that off too.
+- Check that Object Cache Pro is really off. On the source server, this should print nothing (switch out example.com with your new website URL):
+
+ls /var/www/example.com/object-cache-pro-configs.php 2>/dev/null
+If it lists the file, switch Object Cache Pro off for that site in the app again before continuing.
+
+Step B. Delete the object-cache.php file (origin server)
+
+After disabling Redis caching, you can make sure this file is deleted for your website on your origin server with the following command (replace example.com with your website URL):
+
+rm /var/www/example.com/htdocs/wp-content/object-cache.php
+
+Step C. After migrating (destination server, as root)
+Run this once. It updates the migrated site’s wp-config.php for the new server’s Redis setup. It is safe to run more than once – replace “example.com” with your website URL:
+f=/var/www/example.com/wp-config.php
+# Object cache: point at the new object-cache Redis socket
+sed -i 's|/var/run/redis/redis-server.sock|/var/run/redis-object/redis-object.sock|g' "$f"
+# Nginx Helper: add the username/password lines the new page-cache Redis needs
+# (GridPane fills in the real values when you switch Redis page caching on)
+if grep -q "RT_WP_NGINX_HELPER_REDIS_PREFIX" "$f" && ! grep -q "RT_WP_NGINX_HELPER_REDIS_USERNAME" "$f"; then
+sed -i "/RT_WP_NGINX_HELPER_REDIS_PREFIX/a //define('RT_WP_NGINX_HELPER_REDIS_PASSWORD', '');" "$f"
+sed -i "/RT_WP_NGINX_HELPER_REDIS_PREFIX/a //define('RT_WP_NGINX_HELPER_REDIS_USERNAME', '');" "$f"
+fi
+Then, in the GridPane app on the new server, switch caching back on for each site: Redis page caching, and Redis object caching or Object Cache Pro. Switching them on sets each site’s Redis username, password, and database for the new server.
+
+Step D. Check it worked (destination server)
+Object cache: should show “Status: Connected”:
+gp wp {site} redis status
+E.g:
+gp wp example.com redis status
+Page cache: the second request should show “x-grid-srcache-fetch: HIT””
+curl -sI https://{site}/ | grep -i x-grid-srcache-fetch
+curl -sI https://{site}/ | grep -i x-grid-srcache-fetch
+Run these before you point DNS at the new server. Until then, use a local hosts file entry, or replace the curl commands with:
+curl -sI --resolve {site}:443:{new-server-ip} https://{site}/.
```
