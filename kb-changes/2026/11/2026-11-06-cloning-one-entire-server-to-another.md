# Cloning One Entire Server to Another

- Status: changed
- Interval: 2026-10-21 → 2026-11-06
- Article: https://gridpane.com/kb/cloning-one-entire-server-to-another
- Cited by: not recorded for this backfilled interval
- Extracted text, not the published HTML: code blocks and tables may reflow.

## Diff

```diff
--- 2026-10-21
+++ 2026-11-06
@@ -1,11 +1,24 @@
-Introduction
-GridPane makes moving your websites from one server to another a simple process. This article will walk you through the available configuration options and offers some tips for before and after you start the cloning process.
+Important
+
+Prior to Ubuntu 26.04 Percona or MariaDB database options used to be interchangeable, but they no longer are. When you move, clone or restore a site, always keep it on the same database type it came from: Percona to Percona, or MariaDB to MariaDB. Moving a site between the two types is likely to fail, and support for fixing those failures is limited. If a move between types does go wrong, the fix will almost always be to redo it onto a server with the matching database type.
+
 Table of Contents
+- Introduction
 - Preparation: Before You Begin
 - Configure Your Server Clone
 - The Cloning Process
+- Cloning from 20.04 to 26.04
 - Safety First
 
+Introduction
+GridPane makes moving your websites from one server to another a simple process. For the most reliable and fastest migration, we recommend you check out our custom-built Migrately CLI tool.
+Migrately
+Migrately is what our own support team uses to move WordPress sites on our fully managed service from one server to a brand-new one. This is now available to everyone using GridPane:
+Migrately – A CLI Tool for Full Server to Server Cloning
+Server Cloning Tool
+This article will walk you through the server cloning tool that can be found in Tools page of your GridPane account dashboard. It details how the tool works and offers some tips for before and after you start the cloning process.
+Please note that if you are migrationg to a new Ubuntu 26.04 server from a 20.04 server or earlier, you may need to run a few commands directly via the command line to finish your migration. 
+
 Canary Sites
 
 Canary sites are skipped during the cloning process and so are not transferred from your origin server over to your destination server.
@@ -24,6 +37,8 @@
 If you’ve added anything custom, such as installing additional software or server-level cronjobs, then you will also need to manually move/install/recreate these on your new server if they are still needed.
 Disk Space
 Ensure that your destination server has ample disk space. This means that should you have at least double enough for all your sites, with space left over.
+Migrating from Ubuntu 20.04 to 26.04
+Please see this section before you continue: Migrating from 20.04
 
 Configure Your Server Clone
 To get started, head over to the Tools page in your GridPane account and then select the Server Clone in the Tools.
@@ -54,8 +69,6 @@
 
 We will also duplicate your site-specific PHP in settings and PHP process manager settings that GP-CLI manages, alongside the GP-CLI adjusted site-specific Nginx settings and any includes in your site-level Nginx or OpenLiteSpeed (OLS) directory.
 One setting that does not transfer over when cloning is: AutoSSL. This setting is generally only relevant for multisite networks where you want to provision SSL certificates for new Alias domains automatically.
-Cloning to Ubuntu 22.04 Servers
-The default system user settings will be applied when you clone websites to Ubuntu 22.04 servers from 18.04 and/or 20.04 servers. This means the system user will have both SFTP and SSH access enabled. 
 
 Multisite Cloning and Improvements
 
@@ -65,5 +78,50 @@
 
 *Developer plan and above only
 
+Cloning from Ubuntu 20.04 to 26.04
+There are a few additional steps that may be needed when migrating to a new 26.04 server, which requires running a few commands directly on your server. If this is your first time connecting to a server via SSH, please see the following articles to get started:
+
+Step 1. Generate your SSH Key
+Step 2. Add your SSH Key to GridPane (also see Add default SSH Keys)
+Step 3. Connect to your server by SSH as Root user (we like and use Termius)
+
+Step A. Before you migrate (source server, in the GridPane app)
+- For every site you’re migrating, switch Redis page caching to FastCGI (or off). FastCGI keeps your sites cached during the move and doesn’t use Redis.
+- For every site, switch Redis object caching off. If the site uses Object Cache Pro, switch that off too.
+- Check that Object Cache Pro is really off. On the source server, this should print nothing:
+
+ls /var/www/*/object-cache-pro-configs.php 2>/dev/null
+If it lists a site, switch Object Cache Pro off for that site in the app again before continuing.
+
+Step B. Delete the object-cache.php file
+After disabling Redis caching, you can make sure this file is deleted for each website on your origin server with the following command:
+for f in /var/www/*/htdocs/wp-content/object-cache.php; do { [ -e "$f" ] || [ -L "$f" ]; } || continue; rm -fv "$f"; done
+This will loop through each site and remove this specific file.
+
+Step C. After migrating (destination server, as root)
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
+
 Safety First
 Please ensure that all of your sites have cloned correctly before deleting your origin server, and consider keeping all of the original sites for 1-2 weeks while backups have time to take place.
```
