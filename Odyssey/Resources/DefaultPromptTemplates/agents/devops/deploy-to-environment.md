---
name: "Deploy to environment"
sortOrder: 2
---

Prepare a deployment to the environment below. Verify service health and pending migrations before touching deploy commands.
Output: pre-flight checklist (env vars, dependencies, feature flags), expected downtime window, and a step-by-step rollback plan with the exact commands.
Check for open feature flags and database schema changes that could cause breakage. If environment type (staging/prod) or deploy method is not specified, ask first.

Environment:

