# GH Inbox Issues — Sidebar Section Design

**Date:** 2026-04-23  
**Status:** Approved

---

## Overview

Add a "GH Inbox" collapsible section to the sidebar, positioned immediately after Schedules (`globalUtilitiesSection`) and before Pinned. Each row is a GitHub issue that arrived via the inbox poller. Single-clicking an issue opens it in the browser. A context menu provides six actions.

---

## Sidebar Placement

The sidebar `List` in `SidebarView.swift` renders sections in this order:

```
globalUtilitiesSection   ← Schedules (existing)
ghInboxSection           ← NEW, inserted here
pinnedSection
agentsSection
groupsSection
projectsSection
peersSection
```

---

## Data Source

Issues are existing `Conversation` records filtered by `githubIssueNumber != nil`. No new SwiftData model is needed.

```swift
@Query(filter: #Predicate<Conversation> { $0.githubIssueNumber != nil },
       sort: \Conversation.startedAt, order: .reverse)
private var ghIssues: [Conversation]
```

The section header badge shows the count of issues where no session is currently running (i.e. unhandled).

---

## Row Appearance

Each row shows:
- **Status dot** — color-coded by agent activity
  - 🔵 Blue: a session exists and is `.running`
  - 🟠 Orange: a session exists but is paused/queued (not running)
  - 🟢 Green: no session yet (unassigned)
- **Issue number + title** — `#N title`, truncated to one line
- **Agent label** (optional trailing text) — name of the assigned agent/group if one exists

Single-click: opens `conversation.githubIssueUrl` in the default browser via `NSWorkspace.shared.open(_:)`.

---

## Context Menu — 6 Actions

```
Open in GitHub          → NSWorkspace.shared.open(issueUrl)
Run Now                 → AppState.ghIssueRunNow(_:modelContext:)
Open Conversation       → windowState.selectedConversationId = conv.id
                          (disabled / grayed if no messages exist yet)
──────────────────────
Assign & Run…           → agent/group picker popover → override + run
──────────────────────
Close Issue             → sidecar command ghIssueClose, then archive conv
Delete                  → delete Conversation from modelContext (local only)
```

### Open in GitHub
Calls `NSWorkspace.shared.open(URL(string: conv.githubIssueUrl!)!)`. Always enabled.

### Run Now
`AppState.ghIssueRunNow(_:modelContext:)` — Swift-only method, no new wire command needed:

- If no session exists → calls the same session-creation path as `handleGHIssueTriggered`, sending the existing `session.create` wire command with the issue's agent assignment.
- If a session exists but is not running → sends the existing `session.resume` wire command.
- If a session is already running → no-op (menu item disabled).

### Open Conversation
Sets `windowState.selectedConversationId = conv.id` and scrolls the sidebar to reveal it in its project thread list. Disabled (grayed) if the conversation has no messages yet (i.e. the agent hasn't started).

### Assign & Run…
Shows an inline popover (reuses `AgentPickerPopover`) listing all agents and groups. On selection:
1. If a running session exists, cancel it first.
2. Update `conversation.session?.agentId` override (or store override in a new optional `Conversation.ghOverrideAgentId: UUID?` field).
3. Call `ghIssueRunNow` with the overridden agent.

The selected agent/group replaces the routing-label-derived assignment permanently for this issue.

### Close Issue
1. Sends new sidecar command `ghIssueClose(repo: String, number: Int)`.
2. Sidecar runs `gh issue close --repo <repo> <number>`.
3. On success, sidecar fires `gh.issue.closed { repo, number }` event.
4. Swift side: archive the conversation (`conversation.isArchived = true`), removing it from the inbox list.

### Delete
Deletes the `Conversation` from `ModelContext` locally. Does not touch GitHub. Preceded by a confirmation alert.

---

## New Wire Protocol

### Command (Swift → Sidecar)

**`SidecarCommand.ghIssueClose`**
```swift
case ghIssueClose(repo: String, number: Int)
```
JSON wire: `{ "command": "gh.issue.close", "repo": "owner/repo", "number": 42 }`

### Event (Sidecar → Swift)

**`SidecarEvent.ghIssueClosed`**
```swift
case ghIssueClosed(repo: String, number: Int)
```
JSON wire: `{ "event": "gh.issue.closed", "repo": "owner/repo", "number": 42 }`

---

## New Swift Files / Changes

| File | Change |
|---|---|
| `SidebarView.swift` | Add `ghInboxSection`, `ghInboxSectionHeader`, `GHInboxIssueRow` view, insert section in `List` |
| `SidecarProtocol.swift` | Add `ghIssueClose`, `ghIssueRunNow` commands; `ghIssueClosed` event |
| `AppState.swift` | Add `ghIssueRunNow(_:modelContext:)`, `handleGHIssueClosed(_:)` |
| `sidecar/src/types.ts` | Add `GHIssueCloseCommand`, `GHIssueClosedEvent` |
| `sidecar/src/ws-server.ts` | Handle `gh.issue.close` command |
| `Conversation.swift` | Add optional `ghOverrideAgentId: UUID?` field |

---

## Accessibility Identifiers

| Element | Identifier |
|---|---|
| Section container | `sidebar.ghInboxSection` |
| Section header button | `sidebar.ghInboxSection.header` |
| Issue row | `sidebar.ghInboxRow.<conv.id.uuidString>` |
| Badge | `sidebar.ghInboxSection.badge` |
| Create issue button | `sidebar.ghInboxSection.createButton` |

---

## Out of Scope

- Snooze / defer
- Filter by repo or label
- Inline comment posting
- PR creation from issue
