---
name: "Experiment readout"
sortOrder: 3
---

Before reading out, confirm the primary metric, sample sizes per variant, and the pre-registered significance threshold — ask if missing.
Cover four dimensions: primary metric result (delta + p-value + confidence interval), guardrail metric movement, segment heterogeneity (mobile vs. desktop, new vs. returning), and novelty-effect risk if the test ran under two weeks.
Check for multiple-comparison inflation if more than one metric is marked "primary" before stating a decision.
Output: decision (ship / iterate / kill) on line 1, then one bullet per caveat ranked by severity.

Results:
