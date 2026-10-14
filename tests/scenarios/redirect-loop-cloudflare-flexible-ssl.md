# Scenario: redirect loop from Cloudflare Flexible SSL

## Prompt

"example.com redirects to itself and never loads; it's behind Cloudflare."

## Expected agent path

1. `gridpane-incident-triage` (redirect loop branch).
2. Check the redirect chain with `curl -sSI https://example.com` and inspect the
   `Location` headers.
3. Hand off to `gridpane-security/references/cloudflare.md`: check Cloudflare SSL
   mode (should be **Full (strict)**) — Flexible is the classic cause — and check
   the WordPress site URL.
4. Changing the SSL mode is a Cloudflare-dashboard action; the agent explains the
   effect and the risk (a wrong origin certificate breaks Full (strict)) before
   the user changes it.
5. Verify with `curl -sSI` returning a single 200/30x hop and the site loading.

## Skills that must lead here

- `gridpane-incident-triage` (redirect-loop branch)
- `gridpane-security` + `references/cloudflare.md`
- `gridpane-wordpress` (site URL mismatch)

## Anti-patterns to avoid

- Blaming WordPress first; the loop is usually SSL mode at the edge.
- Setting Full (strict) without a valid origin certificate.
