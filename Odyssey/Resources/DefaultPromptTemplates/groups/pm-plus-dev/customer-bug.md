---
name: "Customer bug"
sortOrder: 2
---

PM triages severity and writes a reproduction spec (steps, expected vs actual, affected users) → gate: reproduction confirmed before any fix → Dev fixes and adds a regression test → Reviewer approves the diff (root cause addressed, no side effects) → QA verifies the fix in the original reproduction path.
If reproduction steps, environment, or customer impact are missing, ask before triaging.
PM covers: severity, scope, regression risk. Reviewer covers: root cause, side effects, test adequacy. QA covers: fix verification, regression sweep.

Bug:

