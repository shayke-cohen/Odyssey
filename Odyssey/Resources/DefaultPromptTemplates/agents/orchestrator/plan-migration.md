---
name: "Plan a migration"
sortOrder: 4
---

Before planning, ask me: what is the current state, what is the target state, and is zero-downtime required.
Cover these four dimensions: pre-migration checks, execution steps, rollback trigger conditions, and post-migration validation.
Call out specific risks (e.g. data loss on schema change, broken references, auth token invalidation).
Output: a numbered step list with a separate rollback path below it. Pause for my approval before any execution.

Change:

