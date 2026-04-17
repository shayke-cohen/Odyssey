---
name: "Subtle-change review"
sortOrder: 5
---

Ask for the change diff and the surrounding context (callers, contracts) if not provided.
Reviewer enumerates every invariant the changed code must preserve, stated as explicit conditions.
Coder demonstrates — via reasoning or a test — how each invariant holds after the change.
Reviewer either confirms each proof or requests a stronger argument; no sign-off until all are confirmed.
Output: annotated diff with an invariant table showing condition, evidence, and reviewer verdict.

Change:

