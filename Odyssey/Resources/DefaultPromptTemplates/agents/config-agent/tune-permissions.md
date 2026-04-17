---
name: "Tune permissions"
sortOrder: 4
---

Before tuning, list the agent's actual recurring tasks and confirm whether it has ever needed permissions it currently lacks — ask if the task list is unclear.
Audit three categories: over-broad allows (e.g. Bash:* when only specific commands are used), missing denies for sensitive paths (credentials, config files), and MCP scopes wider than the agent's stated role.
Check the agent's recent transcript or hook logs before removing a permission — don't revoke something it actively uses.
Output: one bullet per change (add / remove / narrow), severity label (critical / advisory), and the one-line rationale for each.

Agent:
