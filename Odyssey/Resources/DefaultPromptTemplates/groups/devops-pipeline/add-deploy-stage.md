---
name: "Add deploy stage"
sortOrder: 2
---

If the target environment, deploy tool, or smoke-test endpoint is unknown, ask before starting.
DevOps designs the deploy stage (artifact promotion → deploy → smoke tests → health check) and produces a `deploy-plan.md`; get approval before editing the pipeline.
Coder adds the deploy job to the existing workflow file and wires in environment secrets.
DevOps triggers a staging deploy, confirms health-check passes, and reports the new end-to-end pipeline duration.
Gate: staging deploy must succeed and health check must return 200 before this task is done.
