# Task Board Patterns

The task board is a shared work queue where users post tasks and agents claim and execute them.

## Reading the Board

```
task_board_list()                            // all tasks
task_board_list(status: "ready")             // unclaimed tasks available for work
task_board_list(assigned_to: "Orchestrator") // tasks assigned to you
```

## Claiming Tasks

When you see a "ready" task you can handle, atomically claim it:

```
task_board_claim(task_id: "uuid")
```

This sets the task to "inProgress" and assigns it to you. If another agent already claimed it, the call returns an error — move on to the next task.

## Creating Subtasks

For complex tasks, decompose into subtasks:

```
task_board_create(
  title: "Research sorting algorithms",
  description: "Compare quicksort, mergesort, and heapsort for our use case",
  priority: "high",
  parent_task_id: "parent-uuid",
  status: "ready"
)
```

Then delegate each subtask to a specialist and link the conversation:

```
result = peer_delegate_task(to: "Researcher", task: subtask.title, wait_for_result: true)
task_board_update(task_id: subtask_id, status: "done", result: result, conversation_id: session_id)
```

## Completion Flow

When all subtasks are done, mark the parent done:

```
task_board_update(task_id: parent_id, status: "done", result: "Summary of completed work...")
```

## Status Lifecycle

```
backlog → ready → inProgress → done | failed | blocked
```

- **backlog** — Draft, not yet available. Only the user promotes to ready.
- **ready** — Available for claiming. Orchestrator picks these up.
- **inProgress** — Actively being worked on.
- **done** — Completed successfully.
- **failed** — Completed with errors.
- **blocked** — Waiting on external input.

## Polling Pattern (Continuous Mode)

When asked to monitor the board continuously:

```
1. tasks = task_board_list(status: "ready")
2. For each task, sorted by priority (critical > high > medium > low):
   a. task_board_claim(task_id)
   b. Analyze scope, check peer_list_agents() for available specialists
   c. Simple task → peer_delegate_task to one agent
   d. Complex task → create subtasks, delegate each
   e. Link conversations via task_board_update(conversation_id: ...)
   f. Wait for results, update status
3. Repeat after a short pause
```

## Best Practices

- Always claim before starting work — prevents duplicate execution.
- Link every task to its conversation so the user can click through.
- Use subtasks for anything that involves more than one agent.
- Report results in the `result` field when marking done — this is visible to the user.
- If stuck, mark as `blocked` with an explanation, not `failed`.
- Never leave a claimed task without updating its status.
