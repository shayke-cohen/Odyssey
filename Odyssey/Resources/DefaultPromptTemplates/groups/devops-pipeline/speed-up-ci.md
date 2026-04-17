---
name: "Speed up CI"
sortOrder: 3
---

If access to recent pipeline run logs or caching config is unavailable, ask before starting.
DevOps profiles the current pipeline — per-step timings, cache hit rates, parallelism gaps — and produces a `ci-profile.md` with before numbers and ranked optimizations.
Get approval on the optimization plan, then Coder implements changes (dependency caching, job splitting, test sharding).
DevOps re-runs the pipeline, records after timings, and confirms at least 50% total time reduction.
Gate: verified before/after numbers must be included in the final report before this task is done.
