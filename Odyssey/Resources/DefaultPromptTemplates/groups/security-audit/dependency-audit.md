---
name: "Dependency audit"
sortOrder: 2
---

Coder scans all dependencies for known CVEs and produces a findings list (package, CVE, severity, fix version) → gate: findings confirmed before remediation planning → Reviewer proposes a remediation plan ranked by severity with effort estimates and breaking-change risk per upgrade.
Coder covers: direct and transitive dependencies, CVE severity, available fix versions. Reviewer covers: upgrade effort, breaking-change risk, interim mitigations for unfixable findings.

