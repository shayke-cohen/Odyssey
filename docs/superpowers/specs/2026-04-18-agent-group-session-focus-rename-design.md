# Design: Agent/Group Session Auto-Focus and Rename

**Date:** 2026-04-18
**Status:** Approved

## Problem

Two related UX gaps when creating a new chat from an agent or group:

1. **Focus**: The new conversation is selected (`selectedConversationId` is set) but the agent/group DisclosureGroup in the sidebar does not expand to show it. The root cause is a SwiftData `@Query` timing issue — `handleConversationSelectionChange` fires synchronously after selection, but the `conversations`/`allSessions` query arrays haven't refreshed yet, so the agent/group lookup fails.

2. **Naming**: Agent/group chats are created with `topic: agent.name` or `topic: group.name`. The auto-rename guard in `autoNameConversation` only triggers on `"New Chat"` or `nil`, so these sessions are never auto-renamed from the first message. Additionally, conversation rows inside `AgentSidebarRowView` and `GroupSidebarRowView` are plain buttons with no context menu, so there is no manual rename option.

## Solution: Approach A

Set initial topic to `nil` for agent/group chats, auto-rename on first message, and add a rename context menu to conversation rows in agent/group sidebar sections.

## Feature 1: Auto-Focus New Session in Tree

All changes are in `SidebarView.swift`.

### Direct expansion (covers sidebar-initiated sessions)

Add `expandedAgentIds.insert(agent.id)` in `startSession(with:)` before setting `selectedConversationId`. This covers:
- Agent sidebar row `+` button
- Agent context menu "New Session"
- `selectOrCreateAgentChat` (tapping agent name)

Add `expandedGroupIds.insert(group.id)` in three group creation sites:
- `groupsSection` `onNewChat` closure
- `groupsSection` context menu "Start Chat"
- `selectOrCreateGroupChat` creation branch

### Deferred retry (covers picker-originated sessions)

In `sidebarList.onChange(of: windowState.selectedConversationId)`, after the immediate `handleConversationSelectionChange(selectedId)` call, also dispatch:
```swift
Task { @MainActor in handleConversationSelectionChange(selectedId) }
```
This gives SwiftData one runloop cycle to refresh the query, catching sessions created via `AgentPickerPopover` and `GroupPickerPopover`.

## Feature 2: Session Renaming (Auto + Manual)

### Part A: Nil initial topic + auto-rename on first message

Change `topic` from agent/group name to `nil` in three creation paths:

| File | Location | Change |
|---|---|---|
| `AgentPickerPopover.swift` | `openThread(agent:)` | `agent?.name ?? "Thread"` → `nil` |
| `SidebarView.swift` | `startSession(with:)` | `agent.name` → `nil` |
| `AppState.swift` | `startGroupChat(...)` | `group.name` → `nil` (autonomous stays `"\(group.name) — Autonomous"`) |

The existing `autoNameConversation` guard (`topic == "New Chat" || topic == nil`) already fires for `nil` topics. Auto-rename triggers on first user message via `isFirstChat` check in `ChatView`.

**Format update for group chats**: In `autoNameConversation`, when `convo.sourceGroupId != nil`, omit the agent-name prefix. Use just the truncated message text rather than `"AgentName: message"`, since the group context is already shown by the DisclosureGroup label.

```swift
let isGroupChat = convo.sourceGroupId != nil
let prefix = isGroupChat ? nil : convo.primarySession?.agent?.name
convo.topic = prefix.map { "\($0): \(truncated)" } ?? truncated
```

### Part B: Manual rename context menu

Add `onRename: ((Conversation) -> Void)?` parameter to both `AgentSidebarRowView` and `GroupSidebarRowView`.

In their inner `ForEach` conversation rows, add:
```swift
.contextMenu {
    Button("Rename\u{2026}") { onRename?(conv) }
}
```

Wire from `SidebarView.agentSidebarRow`:
```swift
onRename: { conv in
    renameText = conv.topic ?? ""
    renamingConversation = conv
}
```

Wire from `SidebarView.groupsSection` for `GroupSidebarRowView` with the same pattern.

The existing "Rename Conversation" alert in `SidebarView` (line 188) handles the rename and save — no new alert needed.

## Files Changed

| File | Changes |
|---|---|
| `Odyssey/Views/MainWindow/SidebarView.swift` | Expansion inserts in 4 methods, deferred Task in onChange, onRename wiring in agentSidebarRow and groupsSection |
| `Odyssey/Views/MainWindow/AgentSidebarRowView.swift` | Add `onRename` param, context menu on conversation rows |
| `Odyssey/Views/GroupLibrary/GroupSidebarRowView.swift` | Add `onRename` param, context menu on conversation rows |
| `Odyssey/Views/MainWindow/AgentPickerPopover.swift` | Change `topic` to `nil` |
| `Odyssey/App/AppState.swift` | Change group chat `topic` to `nil` |
| `Odyssey/Views/MainWindow/ChatView.swift` | Update `autoNameConversation` format for group chats |

## Out of Scope

- Renaming autonomous mission sessions (keep descriptive `"\(group.name) — Autonomous"` topic)
- Renaming project quick-chat threads (separate UX, already have rename via sidebar)
- Auto-rename for project "New Thread" sessions
