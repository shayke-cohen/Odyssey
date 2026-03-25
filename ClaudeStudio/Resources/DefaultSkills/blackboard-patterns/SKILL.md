---
name: blackboard-patterns
description: Conventions for reading and writing structured data to the ClaudPeer blackboard.
category: ClaudPeer
triggers:
  - blackboard
  - write findings
  - share results
  - structured data
  - knowledge store
---

# Blackboard Patterns

The blackboard is a shared key-value store where agents write structured findings and read each other's results. It decouples producers from consumers -- you don't need to know who will read your data.

## Key Naming Conventions

Keys use dot-separated namespaces: `{phase}.{topic}.{subtopic}`

### Standard Namespaces

| Prefix | Purpose | Example |
|---|---|---|
| `research.*` | Findings from investigation | `research.sorting.top3` |
| `impl.*` | Implementation status/artifacts | `impl.mergesort.status` |
| `review.*` | Review findings and decisions | `review.mergesort.approved` |
| `test.*` | Test results | `test.unit.passed` |
| `docs.*` | Documentation status | `docs.readme.status` |
| `devops.*` | Infrastructure operations | `devops.deploy.status` |
| `decision.*` | Agreed-upon decisions | `decision.algorithm.choice` |
| `pipeline.*` | Workflow coordination | `pipeline.phase` |
| `workspace.*` | File readiness signals | `workspace.mergesort.swift.ready` |

### Naming Rules

- Use lowercase with dots as separators.
- Be specific: `research.sorting.memory_analysis` not `research.data`.
- Include the component name: `impl.mergesort.status` not `impl.status`.
- For arrays, use the plural: `research.sorting.candidates`.

## Standard Status Values

When writing status fields, use these standard values consistently:

- `pending` -- work not yet started
- `in_progress` -- actively being worked on
- `done` -- completed successfully
- `failed` -- completed with errors (include error details)
- `blocked` -- waiting on a dependency (include what it's waiting for)

```
blackboard_write(key: "impl.mergesort.status", value: "{\"status\": \"in_progress\", \"startedAt\": \"2026-03-21T12:04:00Z\"}")
```

## JSON Value Conventions

Always write valid JSON. Use consistent structures for common data types:

### Findings

```json
{
  "summary": "Mergesort is the best fit for our constraints",
  "details": ["Handles 10M rows in 8GB RAM", "O(n log n) worst case", "Stable sort"],
  "sources": ["https://en.wikipedia.org/wiki/Merge_sort"],
  "confidence": "high"
}
```

### Decisions

```json
{
  "choice": "mergesort",
  "reason": "Best memory/performance tradeoff for 10M rows in 8GB",
  "alternatives_considered": ["quicksort", "heapsort"],
  "decided_by": "Researcher + Coder consensus"
}
```

### Artifacts

```json
{
  "status": "done",
  "file": "mergesort.swift",
  "tests": "mergesort_tests.swift",
  "loc": 142
}
```

### Test Results

```json
{
  "status": "done",
  "passed": 12,
  "failed": 1,
  "skipped": 0,
  "bugs": [
    {"id": "bug-1", "severity": "medium", "description": "Off-by-one in merge phase", "file": "mergesort.swift", "line": 87}
  ]
}
```

## When to Use the Blackboard vs Messages

| Scenario | Use Blackboard | Use Message |
|---|---|---|
| Research findings other agents may need later | Yes | No |
| "I'm done, your turn" coordination | No | Yes (`peer_send_message`) |
| Status tracking across a pipeline | Yes | No |
| Quick question for another agent | No | Yes (`peer_chat_start`) |
| Decision that must be referenced later | Yes | Also message the decision |
| Error/failure details | Yes | Also alert via message |

**Rule of thumb:** If the data needs to persist or be discoverable by agents that don't know about it yet, use the blackboard. If it's transient coordination, use messages.

## Reading Patterns

### Specific key

```
blackboard_read(key: "research.sorting.top3")
```

### Glob query

```
blackboard_query(pattern: "research.sorting.*")
→ returns all entries under research.sorting
```

### Subscribe to changes

```
blackboard_subscribe(pattern: "impl.*")
→ notified when any implementation status changes
```

## Scoping

Blackboard entries can be scoped to a shared workspace using the `scope` parameter:

```
blackboard_write(key: "impl.mergesort.status", value: "...", scope: "workspace-id")
```

Scoped entries are only visible within that workspace context. Unscoped entries are global.
