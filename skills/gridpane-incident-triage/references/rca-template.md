# Root-cause analysis template

A short, factual write-up for the client or the team after an incident. Keep it
plain: what happened, when, how bad, why, what fixed it, and what stops it
recurring. Do not pad it.

---

## Incident summary

- **Title:**
- **Date/time (with timezone):**
- **Duration:**
- **Detected by:** (Monit alert, customer report, monitoring)
- **Severity:** (all sites down / one site down / degraded / cosmetic)

## Impact

- **Services affected:** (e.g. `example.com` only; or all sites on server X)
- **User-visible effect:** (error code, slow pages, failed checkouts)
- **What still worked:** (say so, to scope the damage honestly)

## Timeline

| Time | Event |
|---|---|
| HH:MM | First symptom / alert |
| HH:MM | First check run; what it showed |
| HH:MM | Cause identified |
| HH:MM | Fix applied ([WRITE] confirmed by owner) |
| HH:MM | Service verified healthy |

## Root cause

One or two paragraphs. State the actual mechanism, not a symptom. Name the
resource or code path that failed and why, with the evidence:

- Which metric/log proved it (e.g. `pm.max_children` warnings in the FPM log at
  the same timestamps as the 502s).
- What triggered it (traffic spike, plugin update, disk filling, DNS change).
- Why the safety nets did not catch it earlier, if relevant.

## Fix

- **Immediate:** the exact action taken, and the rollback that was available.
- **Verification:** the observable check that confirmed recovery.

## Prevention

- Follow-ups with owners, e.g.:
  - Raise pool size / add RAM (with the trade-off stated).
  - Replace or fix the offending plugin/query.
  - Add log rotation or a disk-space alert.
  - Adjust backup schedule to avoid table-lock windows.

## Open questions

Anything still unverified, to hand to the owner (mirror into
`OPEN-QUESTIONS.md` if it belongs in the repo).

---

Last verified: 2026-10-07
