---
name: delegation-patterns
description: Patterns for decomposing tasks and delegating work to specialist agents.
category: ClaudPeer
triggers:
  - delegate
  - break down task
  - orchestrate
  - coordinate agents
  - pipeline
---

# Delegation Patterns

This skill covers how to decompose complex tasks into subtasks and delegate them to specialist agents using `peer_delegate_task`.

## Writing Effective Task Descriptions

Every delegation should include:

1. **Goal** -- what the agent should accomplish (one sentence)
2. **Context** -- relevant background, blackboard keys to read, files to look at
3. **Constraints** -- limitations, coding standards, performance requirements
4. **Expected output** -- what the delegate should produce (files, blackboard entries, messages)

### Good Example

```
peer_delegate_task(
  to: "Coder",
  task: "Implement an external mergesort that handles 10M integer rows within 8GB RAM",
  context: "See blackboard research.sorting.analysis for algorithm details. Working in shared workspace ws-1. Target file: mergesort.swift. Follow existing Swift code style in the project.",
  wait_for_result: true
)
```

### Bad Example

```
peer_delegate_task(to: "Coder", task: "Write some sorting code", wait_for_result: true)
```

Missing: which algorithm, memory constraints, where to write, what to reference.

## Choosing Wait Strategy

### `wait_for_result: true` (Blocking)

Use when **the next step depends on this result**:

- Research must complete before implementation can start
- Implementation must complete before review can start
- You need the delegate's output to synthesize a final answer

The tool call blocks until the delegate finishes. Your agent is paused.

### `wait_for_result: false` (Fire-and-forget)

Use when you can **continue working in parallel**:

- Launching multiple independent coding tasks
- Triggering tests while doing other work
- Starting a documentation task alongside implementation

Returns immediately with `{ sessionId: "..." }`. Track progress via the blackboard.

## Pipeline Templates

### Sequential: Research -> Implement -> Review

```
1. peer_delegate_task(to: "Researcher", task: "...", wait_for_result: true)
   → Researcher writes findings to blackboard
2. peer_delegate_task(to: "Coder", task: "...", context: "Read blackboard research.*", wait_for_result: true)
   → Coder writes code and updates blackboard impl.*
3. peer_delegate_task(to: "Reviewer", task: "...", context: "Review code at impl.*", wait_for_result: true)
   → Reviewer writes findings to blackboard review.*
4. Synthesize results from blackboard
```

### Parallel Investigation

Spawn N agents to research different aspects simultaneously:

```
1. peer_delegate_task(to: "Researcher", task: "Research sorting algorithms", wait_for_result: false) → id1
2. peer_delegate_task(to: "Researcher", task: "Research memory optimization", wait_for_result: false) → id2
3. peer_delegate_task(to: "Researcher", task: "Research streaming approaches", wait_for_result: false) → id3
4. Monitor blackboard for research.*.status == "done" (all three)
5. Read all findings, synthesize
```

### Iterative Refinement

Implement, review, fix, re-review. Max 3 cycles to avoid infinite loops:

```
for cycle in 1...3:
  1. peer_delegate_task(to: "Coder", task: "Implement (or fix) ...", wait_for_result: true)
  2. peer_delegate_task(to: "Reviewer", task: "Review ...", wait_for_result: true)
  3. Read blackboard review.*.approved
     - If true → done
     - If false → continue loop with review feedback as context
```

### Fan-out / Fan-in

Delegate N independent tasks, wait for all, then synthesize:

```
1. Analyze task → identify N independent subtasks
2. For each subtask:
     peer_delegate_task(to: appropriate_agent, task: subtask, wait_for_result: false) → store session IDs
3. Monitor blackboard for all subtask statuses == "done"
4. Read all results from blackboard
5. Synthesize final output
```

## Handling Failures

When a delegation fails (timeout, error, unexpected result):

1. **Read the blackboard** for error details the delegate may have written.
2. **Don't retry blindly** -- understand why it failed first.
3. **Provide more context** on retry -- the delegate may have failed due to insufficient information.
4. **Escalate if stuck** -- after 2 failed retries, write a summary to the blackboard and notify the user or parent agent.
5. **Set a timeout expectation** -- if a delegate hasn't updated the blackboard in 5 minutes, check on it via `peer_send_message`.

## Instance Policy Awareness

When delegating, the target agent's instance policy affects routing:

- **`.spawn`** -- a fresh session is created for your task. No queueing.
- **`.singleton`** -- your task joins a queue. May wait if the agent is busy. Best for serialized work like reviews.
- **`.pool(max: N)`** -- up to N parallel instances. Tasks are assigned to idle instances or queued.

For time-sensitive work, prefer delegating to `.spawn` or `.pool` agents. For consistency (e.g., one reviewer sees the full picture), use `.singleton` agents.
