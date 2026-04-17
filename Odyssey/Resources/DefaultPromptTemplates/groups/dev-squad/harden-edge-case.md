---
name: "Harden edge case"
sortOrder: 5
---

Ask for the edge case description and the module it lives in if not provided.
Tester writes a failing test that precisely captures the edge case; output: failing test with a comment explaining the expected behavior.
Coder makes the test pass with the smallest production change that doesn't break existing tests; output: implementation diff.
Reviewer confirms the test is well-scoped, the fix is not over-engineered, and the full test suite is green.
Output: new test + targeted fix, both signed off by Reviewer.

Edge case:

