---
name: "Build CI pipeline"
sortOrder: 1
---

If the repo name, primary language, or test command is unknown, ask before starting.
DevOps designs the pipeline stages (lint → test → build) and produces a `ci-plan.md`; get approval before any files are written.
Coder implements the workflow file (`/.github/workflows/ci.yml` or equivalent) and confirms it parses cleanly.
DevOps applies the config, validates the first run passes all stages, and reports final job durations.
Gate: pipeline must show green on a real PR before this task is done.
