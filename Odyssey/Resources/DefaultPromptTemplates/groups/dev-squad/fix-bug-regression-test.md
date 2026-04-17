---
name: "Fix bug + regression test"
sortOrder: 2
---

Ask for the bug description and a reproduction case if not provided.
Coder identifies the root cause, applies the minimal fix, and notes which invariant was violated; output: patched code with a one-line root-cause comment.
Tester writes a regression test that fails on the unpatched code and passes on the fix; output: test file.
Reviewer verifies the fix is minimal (no unrelated changes) and the test is specific enough to catch regressions.
Output: fix diff + regression test, both approved by Reviewer.

Bug:

