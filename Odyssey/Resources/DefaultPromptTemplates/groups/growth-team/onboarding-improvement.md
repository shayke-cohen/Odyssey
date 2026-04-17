---
name: "Onboarding improvement"
sortOrder: 3
---

Flow:

If the flow name or the step with the highest drop-off is unknown, ask before starting.
Analyst identifies the single highest drop-off step and quantifies it; output: `onboarding-audit.md`.
PM proposes the intervention (copy change, step removal, or UI simplification) tied to the audit finding; Designer mocks it up.
Engineer implements the change; Analyst confirms the relevant funnel event fires correctly in staging.
Gate: the intervention must be traceable to the drop-off finding before it ships.
