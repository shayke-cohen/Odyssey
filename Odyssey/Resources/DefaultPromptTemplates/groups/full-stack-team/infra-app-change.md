---
name: "Infra + app change"
sortOrder: 5
---

Change:

If the change description or which layer is affected first is blank, ask before starting.
DevOps and Backend jointly produce a `deploy-order.md` specifying which layer changes first and what each layer requires from the other; get approval before touching anything.
DevOps applies infra changes and confirms the new resources are healthy; output: infra health report.
Backend deploys app changes against the new infra and runs integration tests; both roles confirm end-to-end before marking complete.
Gate: infra layer must be verified healthy before the app layer is deployed.
