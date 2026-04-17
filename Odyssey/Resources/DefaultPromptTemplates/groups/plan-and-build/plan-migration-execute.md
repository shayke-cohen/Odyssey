---
name: "Plan migration + execute"
sortOrder: 3
---

Planner produces a migration plan with rollback steps for each stage → Coder executes one stage at a time → human approval required before each subsequent stage starts → Reviewer confirms data integrity and no regressions after the final stage.
If target state, affected systems, or rollback constraints are unclear, ask before planning.
Planner covers: stage sequencing, rollback paths, blast-radius estimate. Reviewer covers: data consistency, compatibility, cutover risk.

Change:

