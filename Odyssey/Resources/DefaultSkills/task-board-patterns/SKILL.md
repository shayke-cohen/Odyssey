---
name: task-board-patterns
description: Patterns for creating, updating, and tracking tasks on the Odyssey task board.
category: Odyssey
triggers:
  - task board
  - create task
  - track progress
  - task list
  - task status
---

# Task Board Patterns

The task board is a project-scoped system for tracking work items across agents. Use it to plan, assign, and track tasks through their lifecycle.

## Task Lifecycle

Tasks move through these states:

| State | Meaning |
|---|---|
| `backlog` | Identified but not ready to start |
| `ready` | Ready to be picked up |
| `inProgress` | Actively being worked on |
| `done` | Completed successfully |
| `failed` | Completed with errors |
| `blocked` | Waiting on a dependency |

## Creating Tasks

Use `task_create` to add work items to the board:

```
task_create(
  title: "Implement external mergesort",
  description: "Sort 10M integer rows within 8GB RAM. See blackboard research.sorting.analysis.",
  priority: "high",
  labels: ["implementation", "performance"],
  assignedTo: "Coder"
)
```

### Priority Values

- `critical` — blocks release or other agents
- `high` — must complete this session
- `medium` — should complete soon (default)
- `low` — nice to have

### Good Task Descriptions

Include:
1. **What** — the specific deliverable
2. **Context** — blackboard keys, files, or constraints to reference
3. **Acceptance criteria** — how to know it's done

## Updating Tasks

Call `task_update` when status or details change:

```
task_update(id: "task-id", status: "inProgress")
task_update(id: "task-id", status: "done", description: "Implemented in mergesort.swift, 142 LOC")
task_update(id: "task-id", status: "blocked", description: "Blocked: waiting for research.sorting.analysis on blackboard")
```

Always update status when you begin or complete work so other agents and the user can track progress.

## Listing Tasks

```
task_list()                            // all tasks
task_list(status: "ready")             // only ready tasks
task_list(assignedTo: "Coder")         // tasks for a specific agent
```

## Workflow Patterns

### Orchestrator Planning

Before delegating, create tasks for each work item:

```
1. task_create(title: "Research sorting algorithms", assignedTo: "Researcher", status: "ready")
2. task_create(title: "Implement mergesort", assignedTo: "Coder", status: "backlog")
3. task_create(title: "Review implementation", assignedTo: "Reviewer", status: "backlog")
4. Delegate to Researcher → they mark their task inProgress/done
5. Promote implementation task to ready, delegate to Coder
6. Promote review task to ready once Coder is done
```

### Worker Agent Workflow

When you receive a delegated task:

1. Find your task: `task_list(assignedTo: "YourAgentName", status: "ready")`
2. Mark it in-progress: `task_update(id: "...", status: "inProgress")`
3. Do the work
4. Mark done (or failed/blocked): `task_update(id: "...", status: "done")`

### Blocking and Unblocking

When blocked, record why so other agents can help:

```
task_update(
  id: "...",
  status: "blocked",
  description: "Blocked: need API contract from Designer before implementation can start"
)
```

When the blocker is resolved, promote back to `ready` and notify the assigned agent via `peer_send_message`.

## Task Board vs Blackboard

| Use Task Board | Use Blackboard |
|---|---|
| Tracking work items and their lifecycle | Storing structured findings and data |
| Assigning work to specific agents | Sharing research results or decisions |
| Communicating progress to the user | Coordination signals between agents |
| Planning a multi-step pipeline | Persisting artifacts for later reference |

Use both together: task board for "what needs doing and by whom", blackboard for "what was found and decided".
