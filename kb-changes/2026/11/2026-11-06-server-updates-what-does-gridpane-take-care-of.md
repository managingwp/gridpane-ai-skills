# Server Updates, Maintenance, & Security Patches – What Updates Does GridPane Take Care Of?

- Status: changed
- Interval: 2026-10-21 → 2026-11-06
- Article: https://gridpane.com/kb/server-updates-what-does-gridpane-take-care-of
- Cited by: nothing in `skills/`
- Extracted text, not the published HTML: code blocks and tables may reflow.

## Diff

```diff
--- 2026-10-21
+++ 2026-11-06
@@ -1,29 +1,47 @@
-Introduction
-We often get asked whether anything is necessary on your part to keep your servers up-to-date and secure. In a nutshell, you are not required to maintain your servers, and this is included as a part of our service while they are still attached to your GridPane account.
 Table of Contents
-- What Exactly Does GridPane Take Care Of?
-- Exceptions: Software That You Install
-- What About OS Upgrades?
-
-What Exactly Does GridPane Take Care Of?
-GridPane takes care of all necessary server updates. This includes all security-related updates. For package updates that aren’t security related, these are updated if there’s a benefit in doing so. Many packages that come included as a part of the default OS install are simply not necessary for the operation or security of your servers and can be safely ignored.
-Nothing is required on your part to maintain our default stack or your servers OS. As long as your server is up and running at your IaaS provider, then we will ensure that the server stack is enterprise-ready. More details below.
-
-Unattended upgrades
-Unattended upgrades runs security updates for all system applications. It runs checks twice daily for security updates and is set to install and auto reboot if required at a time you can control. See below.
-
-Server Restarts
-Servers often get restarted at 2.30am UTC to take care of these updates. If this time isn’t convenient for you, you can change your server’s time zone to one that makes sense for your business, and you can also adjust the time where these updates take place.
-To update your time zone and/or default security reboot time, please check out this KB article:
+- Introduction
+- What Does GridPane Take Care Of?
+- Exceptions: Software and Changes You Make
+- What About Ubuntu Version Upgrades?
+
+Introduction
+We often get asked whether you need to do anything to keep your servers up to date and secure. In short, GridPane’s tooling is set up to handle this for you by default while your server is connected to your GridPane account. This article explains what happens automatically, what you can control, and the few things that are up to you.
+
+What Does GridPane Take Care Of?
+Out of the box, GridPane configures your server to keep itself up to date.
+Security updates. Unattended-upgrades is enabled by default and installs security updates for the software on your server. It checks for new security updates twice a day.
+Stack updates. The core services in your LEMP or LOMP stack are also updated regularly to the latest available packages.
+Other packages. A standard Ubuntu installation includes many packages that aren’t needed for your server to run or stay secure. Unattended-upgrades still install security updates for these, but we don’t apply their other, non-security updates. That’s why you may see a message, for example when you log in over SSH, saying some packages can be updated. This is expected, and these updates can be safely ignored.
+With these default settings, nothing is required on your part to keep the default software stack up to date.
+
+Security Reboots
+Some security updates only take effect after a reboot. By default, your server reboots automatically when needed, at 2:30 am server time (UTC unless you’ve changed your server’s time zone – we recommend you match this to the customers served).
+Using GridPane’s tooling, you can change the reboot time or turn off automatic security reboots and reboot on your own schedule. If you turn them off, some updates won’t take effect until you reboot. GridPane’s tooling doesn’t provide an option to turn off security updates themselves.
 How to Change Your Servers Time Zone and Automatic Security Reboot Time
 
-Exceptions: Software That You Install
-For anything external that is installed by yourself and not us here at GridPane, this isn’t something that we would automatically update and is beyond the scope of our support. In these cases, maintenance of this software would be up to you to keep an eye on and take care of. 
-You can learn more about using third-party software in this KB article:
+Monitoring
+Your server’s Monit process manager watches the update system. If unattended-upgrades runs into a problem, Monit detects it and sends a notification to your GridPane account, so we recommend checking your notifications regularly.
+
+Exceptions: Software and Changes You Make
+GridPane’s tooling makes every effort to keep the default software stack up to date. Any software you install yourself isn’t covered, so keeping it updated is up to you. It should also be noted that any other software you install, if configured incorrectly or not kept up to date may block these update mechanisms.
+You can learn more about using third-party software in this KB article: 
 Can I Install Third-Party Software and Services on my GridPane Servers?
 
-What About OS Upgrades?
-When it comes to OS upgrades, for example, Ubuntu 18.04 to 20.04, this is a nontrivial process.
-There’s really no feasible way for us to support this. It’s not the straightforward process that it appears to be on the surface, and it can’t simply be automated. Hiring a sysadmin to manually upgrade the OS of a live production server would be no small investment. 
-Moving from 18.04 to 20.04 will require a newly provisioned 20.04 server and migrating your sites across. While there is some time involved, this is easy to do using the full server clone option, which will copy all your sites and their settings across.
-Cloning One Entire Server to Another
+When Updates Can’t Run
+Automatic updates rely on your server staying in a state where they can run. Updates may fail to install if something on the server gets in the way, such as running out of disk space, package conflicts, software you’ve installed, or changes you’ve made to the server’s configuration. The same applies if you disable automatic updates or remove or change GridPane’s SSH keys or access.
+If something you do, whether intentionally or not, prevents us from maintaining your server or applying updates, the server and anything that results, including security issues, failed updates or data loss, are your responsibility. Any support we provide in these situations is entirely at our discretion and isn’t guaranteed. We may ask you to reverse the changes, or restore our standard configuration where we can.
+Your Monit notifications are the best early warning that updates aren’t running, so it’s worth acting on them promptly.
+
+Non-Standard Ubuntu Installations
+GridPane’s scripts are built for the standard Ubuntu installation. In very rare cases, a cloud provider modifies its Ubuntu installation in a way that stops our scripts from installing correctly, or causes problems later on. This is more likely with very low-cost providers. In either case, we’re unable to support that server.
+If you’re using a provider for the first time, we recommend asking them whether they modify their standard Ubuntu installation in any way, and provisioning a test server before moving any production sites to it.
+
+What About Ubuntu Version Upgrades?
+Moving to a new Ubuntu version means provisioning a new server and migrating your sites to it. Ubuntu includes a tool for upgrading a server in place, but this isn’t supported on GridPane servers.
+Each GridPane server’s software stack is built for a specific Ubuntu version. Upgrading the operating system on its own leaves your server running packages that weren’t designed for the new version, and it will run into problems. Upgrading a GridPane server’s Ubuntu version in place immediately voids our support for that server.
+Even without that, upgrading a live production server in place is risky. The process changes a huge number of packages at once, your sites can go down while it runs, and if something fails partway through there’s no simple way to roll back. That’s why the standard approach across the hosting industry is to build a new server and migrate sites to it, and many managed hosts do this behind the scenes rather than upgrading your existing server. Migrating also means you can test everything on the new server while your sites stay live on the old one, and keep the old server as a fallback until you’re confident.
+
+How This Works on Your Plan
+Fully managed websites. We handle everything, provisioning the new server and migrating your websites, and we’ll work with you directly on timing.
+PeakFreq. We’ll give you at least 90 days’ notice before your Ubuntu version reaches the end of our support period. You can then move your sites to a new server using our tools or another migration method of your choice.
+All other servers. We’ll also give you at least 90 days’ notice before our support for your Ubuntu version ends. We don’t force you to upgrade, but staying on an unsupported version means limited ability to add new sites, security updates may no longer be available, and you may run into issues as our scripts are updated over time.
```
