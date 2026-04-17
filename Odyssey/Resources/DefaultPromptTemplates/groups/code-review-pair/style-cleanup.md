---
name: "Style / conventions cleanup"
sortOrder: 4
---

Ask for the file list and the conventions reference (linter config, style guide) if not provided.
Reviewer scans for naming, formatting, and import-order violations and produces a categorized issue list.
Coder applies fixes file by file; mechanical changes (whitespace, casing) first, structural changes second.
Reviewer does a final pass to confirm no new violations were introduced.
Output: cleaned files + a diff summary grouped by violation category.

Files:

