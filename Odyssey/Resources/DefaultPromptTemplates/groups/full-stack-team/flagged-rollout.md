---
name: "Flagged rollout"
sortOrder: 3
---

Change:

If the change description or feature flag system is blank, ask before starting.
Backend wires the flag in the flag service and gates all affected code paths; Frontend adds the flag guard to UI components; output: `flag-wiring.md`.
Reviewer confirms no code path is reachable without the flag before approving.
DevOps deploys with the flag off, enables it for 1% of traffic, monitors error rate for 10 minutes, then escalates or rolls back.
Gate: error rate must stay below baseline at each traffic increment before proceeding to the next.
