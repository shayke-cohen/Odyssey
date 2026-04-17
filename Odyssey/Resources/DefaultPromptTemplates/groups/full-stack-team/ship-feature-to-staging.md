---
name: "Ship feature to staging"
sortOrder: 1
---

Feature:

If the feature description above is blank, ask before starting.
Backend implements API and data layer; Frontend implements UI — both produce a PR against the feature branch.
Reviewer approves both PRs (tests green, no linting errors) before merge; output: merged feature branch.
DevOps deploys to staging and posts the staging URL; QA signs off on acceptance criteria before this task is done.
Gate: staging deploy must be live and QA sign-off recorded before marking complete.
