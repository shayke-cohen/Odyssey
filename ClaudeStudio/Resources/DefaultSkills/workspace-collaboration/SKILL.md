---
name: workspace-collaboration
description: Conventions for multiple agents sharing a workspace directory without conflicts.
category: ClaudPeer
triggers:
  - shared workspace
  - multiple agents same directory
  - file locking
  - workspace conflicts
---

# Workspace Collaboration

When multiple agents share a workspace directory, follow these conventions to avoid conflicts and coordinate file access.

## Creating and Joining Workspaces

```
workspace_create(name: "sorting-collab")
→ { workspace_id: "ws-1", path: "~/.claudpeer/workspaces/ws-1/" }

workspace_join(workspace_id: "ws-1")
→ { path: "~/.claudpeer/workspaces/ws-1/", participants: ["Researcher", "Coder"] }
```

## Directory Structure

```
workspace/
├── {agent-name}/          # Agent-specific work-in-progress
│   ├── drafts/
│   └── notes/
├── src/                   # Shared source code (final artifacts)
├── docs/                  # Shared documentation
├── tests/                 # Shared test files
└── .workspace-meta.json   # Auto-generated workspace metadata
```

- **Agent subdirectories** (`coder/`, `researcher/`) are owned by that agent. Other agents should read but not write there.
- **Shared directories** (`src/`, `docs/`, `tests/`) require coordination before writing (see below).

## File Locking Protocol

Before writing to a shared file:

1. **Check for locks**: Read the blackboard for `workspace.{filename}.lock`
2. **Acquire lock**: Write `workspace.{filename}.lock = { "agent": "your-name", "since": "timestamp" }`
3. **Write the file**: Perform your edits
4. **Signal readiness**: Write `workspace.{filename}.ready = true`
5. **Release lock**: Delete the lock key by writing `workspace.{filename}.lock = null`

```
blackboard_read(key: "workspace.mergesort.swift.lock")
→ null (not locked)

blackboard_write(key: "workspace.mergesort.swift.lock", value: "{\"agent\": \"Coder\", \"since\": \"2026-03-21T12:04:00Z\"}")

// ... write to mergesort.swift ...

blackboard_write(key: "workspace.mergesort.swift.ready", value: "true")
blackboard_write(key: "workspace.mergesort.swift.lock", value: "null")
```

## Conflict Avoidance

- **Check before writing.** Always check the blackboard for locks and the file's current state before modifying shared files.
- **Work in your agent directory first.** Write drafts in `{agent-name}/drafts/`, then move to the shared location when ready.
- **Don't overwrite without checking.** If another agent has modified a shared file since you last read it, read the latest version first.
- **Communicate major changes.** Before restructuring shared directories or renaming files, announce via `peer_broadcast` or `peer_send_message`.

## Signaling File Readiness

When you've finished writing a file that other agents need:

```
blackboard_write(
  key: "workspace.mergesort.swift.ready",
  value: "{\"ready\": true, \"author\": \"Coder\", \"description\": \"External mergesort implementation\", \"timestamp\": \"2026-03-21T12:10:00Z\"}"
)
```

Other agents can subscribe to readiness signals:

```
blackboard_subscribe(pattern: "workspace.*.ready")
```

## Cleanup

When your work in the workspace is complete:

- Remove any `.lock` entries you created
- Delete temporary files from your agent subdirectory
- Write a final status to the blackboard: `workspace.{your-name}.done = true`
