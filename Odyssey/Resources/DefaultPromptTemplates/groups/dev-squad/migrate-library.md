---
name: "Migrate library X → Y"
sortOrder: 4
---

Ask for the source library, target library, and affected modules if not provided.
Coder produces an API-mapping table (old call → new call) before touching code; Reviewer approves the mapping.
Coder executes the migration module by module; output: diff per module with mapping table references.
Tester runs the existing test suite and writes new tests for any behavior gaps exposed by the migration.
Output: complete migration diff + green test suite; Reviewer confirms no old-library references remain.

From → To:

