---
name: "Growth experiment"
sortOrder: 1
---

Objective:

If the objective above is blank or the current baseline metric is unknown, ask before starting.
PM frames the hypothesis and defines primary metric, sample size, and duration; output: `experiment-brief.md`.
Analyst validates statistical power and specifies the event tracking required; Writer produces variant copy — both keyed to `experiment-brief.md`.
Engineer instruments tracking and builds the variant; get approval on `experiment-brief.md` before any code ships.
Gate: tracking must be verified firing correctly in staging before the experiment launches.
