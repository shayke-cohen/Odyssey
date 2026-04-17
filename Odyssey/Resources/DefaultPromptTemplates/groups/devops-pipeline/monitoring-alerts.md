---
name: "Monitoring + alerts"
sortOrder: 5
---

Service:

If the service name, observability stack (Datadog, Grafana, etc.), or on-call rotation is unknown, ask before starting.
DevOps defines SLOs (availability, latency p99, error rate) and produces a `monitoring-plan.md` with thresholds and dashboard layout; get approval before provisioning.
Coder instruments the service with the required metrics and trace annotations.
DevOps provisions dashboards, alert rules, and paging policy; confirms a test alert fires and resolves correctly.
Gate: at least one alert must fire and auto-resolve in a staging test before this task is done.
