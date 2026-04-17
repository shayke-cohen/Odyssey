---
name: "Refactor module"
sortOrder: 3
---

Ask for the module name and the primary clarity goal (naming, structure, coupling, duplication) if not provided.
Coder refactors toward the stated goal without changing observable behavior; output: diff annotated with the rationale for each structural change.
Tester verifies test coverage is maintained or improved; flags any behavior drift found during testing.
Reviewer checks that the refactor is scoped to the stated goal and no unrelated changes crept in.
Output: refactored module + coverage report; Reviewer and Tester both approve before sign-off.

Module:

