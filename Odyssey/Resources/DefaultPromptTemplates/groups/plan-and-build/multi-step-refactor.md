---
name: "Multi-step refactor"
sortOrder: 5
---

Planner defines the refactor sequence and names an output artifact per step → Coder refactors one step at a time → gate: tests must stay green before the next step starts → Reviewer approves the final diff for readability and architectural consistency.
If the area boundary, test coverage baseline, or end-state design are unclear, ask before planning.
Planner covers: step ordering, coupling risks, naming conventions. Reviewer covers: design consistency, no behavior changes, coverage gaps.

Area:

