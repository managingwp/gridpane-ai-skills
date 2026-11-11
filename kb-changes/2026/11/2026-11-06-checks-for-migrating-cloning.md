# Checks When Migrating/Cloning From One Server to Another

- Status: changed
- Interval: 2026-10-21 → 2026-11-06
- Article: https://gridpane.com/kb/checks-for-migrating-cloning
- Cited by: not recorded for this backfilled interval
- Extracted text, not the published HTML: code blocks and tables may reflow.

## Diff

```diff
--- 2026-10-21
+++ 2026-11-06
@@ -1,14 +1,24 @@
-Introduction
-There will come a time when you need to move your websites from one server to another. This may be to give a specific site more resources, such as moving a growing WooCommerce store to its own individual server or upgrading from an older version of Ubuntu to a newer version.
-Whatever the reason, this article outlines some of the checks that you may want to include in your own internal processes. 
+Important
+
+Prior to Ubuntu 26.04 Percona or MariaDB database options used to be interchangeable, but they no longer are. When you move, clone or restore a site, always keep it on the same database type it came from: Percona to Percona, or MariaDB to MariaDB. Moving a site between the two types is likely to fail, and support for fixing those failures is limited. If a move between types does go wrong, the fix will almost always be to redo it onto a server with the matching database type.
+
 Table of Contents
+- Introduction
+- Migrating from 20.04 to 26.04
 - Confirm Your Clone/Migration Was Successful
 - GridPane Server and/or Site Settings
 - Update Your DNS Records
 - When to Change DNS on a Busy Website
 - IP Addresses and Website Email
 
-Special thanks to Pascal Brennecke for outlining the basis of this article over in our Facebook group.
+Introduction
+There will come a time when you need to move your websites from one server to another. This may be to give a specific site more resources, such as moving a growing WooCommerce store to its own individual server or upgrading from an older version of Ubuntu to a newer version.
+Whatever the reason, this article outlines some of the checks that you may want to include in your own internal processes. 
+
+Migrating from 20.04 to 26.04
+Ubuntu 20.04 is past the end of standard support. Our help for servers on this version is limited to providing guidance on migrating to a supported release, and we can’t help troubleshoot other issues. Security updates are also rarely backported to Ubuntu 20.04 or the software packages it runs (such as PHP, Redis, Percona, and MariaDB). Begin steps to migrate off of this release as soon as possible.
+Redis is set up differently on 22.04 onwards
+Newer servers run separate Redis services for object caching and page caching. Servers on 18.04 and 20.04 use a single shared Redis. If you’re coming from one of those, sites with Redis caching switched on won’t have working caches after the move unless you follow the extra steps in the migration and cloning articles.
 
 Confirm Your Clone/Migration Was Successful
 Just like when migrating a site from another host to GridPane, you should always confirm that your migration was successful.
```
