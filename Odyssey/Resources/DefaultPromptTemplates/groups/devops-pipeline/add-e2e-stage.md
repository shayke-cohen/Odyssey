---
name: "Add E2E stage"
sortOrder: 4
---

If the test framework, browser target, or staging URL is unknown, ask before starting.
DevOps designs the E2E stage (environment spin-up → test run → report → gate-to-prod) and produces an `e2e-plan.md`; get approval before writing any files.
Coder adds the E2E job to the pipeline and wires the production deploy to require it passing.
DevOps triggers the stage against staging, confirms all tests pass, and verifies the production gate blocks on failure.
Gate: E2E stage must block a simulated production deploy on a failing test before this task is done.
