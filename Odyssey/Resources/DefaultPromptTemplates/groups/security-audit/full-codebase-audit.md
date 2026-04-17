---
name: "Full codebase audit"
sortOrder: 1
---

Coder scans for vulnerabilities (injection, auth, secrets, insecure dependencies, logic flaws) and produces a findings list with severity → gate: findings list reviewed before any exploit work → Reviewer prioritises by exploitability and business impact → Tester writes a proof-of-concept for each high/critical finding to confirm exploitability.
Coder covers: OWASP Top 10, secrets in code, dependency CVEs, access control. Reviewer covers: severity ranking, false-positive triage, remediation priority. Tester covers: exploit PoC, reproduction steps, blast radius.

