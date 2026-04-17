---
name: "Retention campaign"
sortOrder: 4
---

Segment:

If the segment definition or current retention rate is unknown, ask before starting.
Analyst sizes the segment, identifies the dominant churn reason, and produces a `retention-brief.md` with target metric and send cadence.
PM proposes the re-engagement mechanic (email, push, in-app); Writer produces subject lines and body copy — both keyed to `retention-brief.md`.
Engineer wires the campaign in the messaging platform; Analyst confirms the segment query and conversion event are tracking before launch.
Gate: segment query must return expected user count and tracking must be verified before the campaign sends.
