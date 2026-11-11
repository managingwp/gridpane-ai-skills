# Clone Over an Existing Site

- Status: changed
- Interval: 2026-10-21 → 2026-11-06
- Article: https://gridpane.com/kb/clone-over-an-existing-site
- Cited by: nothing in `skills/`
- Extracted text, not the published HTML: code blocks and tables may reflow.

## Diff

```diff
--- 2026-10-21
+++ 2026-11-06
@@ -1,3 +1,16 @@
+Important
+
+Prior to Ubuntu 26.04 Percona or MariaDB database options used to be interchangeable, but they no longer are. When you move, clone or restore a site, always keep it on the same database type it came from: Percona to Percona, or MariaDB to MariaDB. Moving a site between the two types is likely to fail, and support for fixing those failures is limited. If a move between types does go wrong, the fix will almost always be to redo it onto a server with the matching database type.
+
+Table of Contents
+- Introduction
+- Step 0. SSL Preparation (if applicable)
+- Step 1. Open the website customizer
+- Step 2. Open the Clone tab
+- Step 3. Run Your Clone Over
+- Step 4. Check Your Destination Site
+- Cloning from 20.04 to 26.04
+
 Introduction
 In addition to our cloning and staging features, GridPane allows you to clone any existing website OVER another existing website.
 This means you have now more than regular staging pushes at your disposal in your development work flow, and it also means that if you keep a copy of one or more websites on another server (without using Failover), you now no longer have to delete them and then run a clone, you simply clone right over it to bring it up-to-date.
@@ -18,27 +31,22 @@
 If you've had WP_DEBUG active, be sure to deactivate it before you proceed as it may cause a fatal error on the destination site.
 
 Step 0. SSL Preparation (if applicable)
-
-An SSL attempt will be made for the destination site IF SSL is enabled on the original site. For this reason, it is important to make sure that your DNS is resolving correctly for the destination site before you attempt your clone over. This will speed up the search and replace because the system will just run a single compound regex.
-
+An SSL attempt will be made for the destination site IF SSL is enabled on the original site. For this reason, it is important to make sure that your DNS is resolving correctly for the destination site before you attempt your clone over. This will speed up the search and replace because the system will just run a single compound regex. 
 If DNS is not resolving the clone over will proceed as normal and the SSL attempt will fail, and GridPane will ensure that all URLs in the database for the new site are replaced with HTTP variants, and this requires 3 passes instead of 1. You can then manually enable SSL later.
-
 You can learn more about GridPane search and replace functions here:
-
 GridPane Database Rewrites and Workflow
 
-Step 1. Navigate to your Sites page
-Click on the Sites link in the GridPane main menu to go to the Sites management page.
+Step 1. Open the website customizer
+First click on the Sites link in the GridPane main menu to go to the Sites management page:
 
-Step 2. Open the site customizer
-Click on the URL of the site you want to clone a duplicate of in the active site’s panel.
+And then click on the URL of the site you want to clone a duplicate of in the active site’s panel.
 
 This will open the site customizer.
 
-Step 3. Open the Clone tab
+Step 2. Open the Clone tab
 Click through to the Clone tab in the site customizer. Here you will find the Migrate/Clone tools. Here you’ll find the cloning and clone over tools:
 
-Step 4. Run Your Clone Over
+Step 3. Run Your Clone Over
 Select your server and then the website you wish to clone over, then click the Migrate / Clone Now button:
 
 Confirm your site and server are correct, and choose whether you want to include database rewrites (run a search and replace):
@@ -47,3 +55,46 @@
 
 Step 5. Check Your Destination Site
 Now your clone over is complete, be sure to check over the destination site is all working as expected, and clear the cache if necessary.
+
+Cloning from 20.04 to 26.04
+There are a few additional steps that may be needed when migrating to a new 26.04 server, which requires running a few commands directly on your server. If this is your first time connecting to a server via SSH, please see the following articles to get started:
+
+Step 1. Generate your SSH Key
+Step 2. Add your SSH Key to GridPane (also see Add default SSH Keys)
+Step 3. Connect to your server by SSH as Root user (we like and use Termius)
+
+Step A. Before you migrate (source server, in the GridPane app)
+- Switch Redis page caching to FastCGI (or off) if applicable. FastCGI keeps your sites cached during the move and doesn’t use Redis.
+- Switch Redis object caching off. If the site uses Object Cache Pro, switch that off too.
+- Check that Object Cache Pro is really off. On the source server, this should print nothing (switch out example.com with your website URL):
+
+ls /var/www/example.com/object-cache-pro-configs.php 2>/dev/null
+If it lists the file, switch Object Cache Pro off for that site in the app again before continuing.
+
+Step B. Delete the object-cache.php file (origin server)
+After disabling Redis caching, you can make sure this file is deleted for your website on your origin server with the following command (replace example.com with your website URL):
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
