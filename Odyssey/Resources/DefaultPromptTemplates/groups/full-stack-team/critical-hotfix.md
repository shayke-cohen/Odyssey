---
name: "Critical hotfix"
sortOrder: 4
---

Issue:

If the issue description, affected service, or severity is blank, ask before starting.
Backend diagnoses root cause and produces a `hotfix-brief.md` (cause, fix, risk, rollback); get approval before writing code.
Coder implements the minimal fix targeting only the root cause; Reviewer checks for regression risk and confirms test coverage.
DevOps deploys to staging, runs smoke tests, gets QA sign-off, then deploys to production with rollback ready.
Gate: smoke tests and QA sign-off must pass on staging before the production deploy proceeds.
