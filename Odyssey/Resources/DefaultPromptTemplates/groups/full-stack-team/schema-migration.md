---
name: "Schema migration"
sortOrder: 2
---

Migration:

If the migration description, database engine, or current schema is blank, ask before starting.
Backend produces a `migration-plan.md` covering forward migration, backfill strategy, rollback script, and verification query; get approval before writing any code.
Coder implements the migration script and backfill job; Reviewer checks for data loss risk and index impact.
DevOps runs the migration on staging, executes the verification query, and confirms row counts match; output: `migration-verification.md`.
Gate: verification must pass on staging before the production migration is scheduled.
