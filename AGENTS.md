# AGENTS.md — Odyssey Codebase Guide

This file is the quick-start guide for coding agents working in this repository.

Note: the workspace folder and product are both `Odyssey`. A few legacy compatibility entry points still accept older `ClaudeStudio` / `ClaudPeer` names, but new code and docs should use `Odyssey`.

## Read This First

Use the project docs in this order:

1. `CLAUDE.md` — primary coding rules, architecture boundaries, and common change workflows
2. `SPEC.md` — what is actually implemented, with feature-by-feature status
3. `TESTING.md` — test layers, accessibility IDs, AppXray/Argus usage
4. `README.md` — onboarding, project structure, launch parameters, protocol overview
5. `sanity-tests.md` and `TEST-REPORT.md` — current sidecar test coverage and recent verification snapshots
6. `system-plan-vision.md` — long-range architecture vision; treat as reference, not the current implementation contract

## Project Snapshot

Odyssey is a two-process macOS app:

```text
SwiftUI app <-> AppState <-> SidecarManager <-> WebSocket JSON <-> WsServer <-> SessionManager <-> Claude Agent SDK
```

- The Swift app owns UI, SwiftData persistence, app state, agent provisioning, and P2P discovery.
- The Bun sidecar owns Claude Agent SDK sessions, WebSocket/HTTP APIs, task board state, blackboard state, and PeerBus tools.
- The contract between them is WebSocket JSON only.

## Non-Negotiable Rules

- Preserve the two-process boundary. Do not couple Swift and TypeScript code directly.
- Keep wire protocol changes synchronized between `Odyssey/Services/SidecarProtocol.swift` and `sidecar/src/types.ts`.
- Do not modify `system-plan-vision.md` unless the user explicitly asks.
- Swift UI/state code must respect Swift 6 strict concurrency. UI-facing state belongs on `@MainActor`.
- The app does not use view models. SwiftUI views use `@Query`, `@Environment(\.modelContext)`, and `AppState`.
- Sidecar code uses Bun + ES modules. Use `.js` import extensions.
- Use the structured logger in sidecar code (`logger.debug/info/warn/error`), not `console.log`.
- Add `.accessibilityIdentifier()` to any new interactive SwiftUI element. Icon-only buttons also need `.accessibilityLabel()`.
- After adding Swift files, regenerate the Xcode project if needed with `xcodegen generate`.

## Repo Map

### Swift app

- `Odyssey/App/OdysseyApp.swift` — app entry point, model container, sidecar connect on appear
- `Odyssey/App/AppState.swift` — global UI state, sidecar event handling, streaming buffers, sheet toggles
- `Odyssey/App/Log.swift` — centralized `OSLog` categories
- `Odyssey/Models/` — all SwiftData `@Model` types
- `Odyssey/Services/` — sidecar lifecycle, protocol, provisioning, git/workspace prep, config sync, logging, P2P
- `Odyssey/Views/MainWindow/` — main shell: welcome, sidebar, chat, inspector, library hub, new session, peer network, task sheets
- `Odyssey/Views/AgentLibrary/` — supporting agent editor/library surfaces used by the hub
- `Odyssey/Views/GroupLibrary/` — supporting group editor/library surfaces used by the hub
- `Odyssey/Views/Catalog/` — catalog detail/install surfaces backing Discover
- `Odyssey/Views/Components/` — shared UI pieces like `MessageBubble`, `ToolCallView`, `StatusBadge`
- `Odyssey/Views/Debug/DebugLogView.swift` — unified log viewer
- `Odyssey/Resources/` — default skills, prompt templates, catalogs, bundled config

### Sidecar

- `sidecar/src/index.ts` — bootstraps WS + HTTP servers
- `sidecar/src/ws-server.ts` — routes commands and broadcasts events
- `sidecar/src/session-manager.ts` — Claude Agent SDK integration, streaming lifecycle
- `sidecar/src/http-server.ts` — blackboard REST API
- `sidecar/src/api-router.ts` — task API routes
- `sidecar/src/types.ts` — sidecar-side wire types
- `sidecar/src/logger.ts` — structured JSON logging
- `sidecar/src/prompts/plan-mode.ts` — plan mode prompt append
- `sidecar/src/stores/` — blackboard, session registry, task board persistence
- `sidecar/src/tools/` — PeerBus, task board, rich display, ask-user, workspace/blackboard tools

### Tests and docs

- `OdysseyTests/` — Swift unit/integration tests
- `sidecar/test/` — Bun unit, integration, API, and E2E tests
- `tests/` — YAML/macOS automation coverage referenced by `TESTING.md`
- `docs/superpowers/` — design and planning docs for newer UX work

## Detailed Code Map

### Core SwiftData models

- `Odyssey/Models/Agent.swift` — reusable agent template: prompt, skills, MCP servers, permissions, model, instance policy, GitHub repo
- `Odyssey/Models/Session.swift` — running agent instance: status, mode, working directory, workspace type, Claude session ID, cost
- `Odyssey/Models/Conversation.swift` — persisted conversation root with participants, messages, pin/archive status, parent linkage
- `Odyssey/Models/ConversationMessage.swift` — text/tool/delegation/blackboard message unit
- `Odyssey/Models/Participant.swift` — user or agent-session participant with role
- `Odyssey/Models/Skill.swift` — reusable skill content and metadata
- `Odyssey/Models/MCPServer.swift` — MCP transport and tool/resource configuration
- `Odyssey/Models/PermissionSet.swift` — allow/deny rules and permission mode
- `Odyssey/Models/SharedWorkspace.swift` — collaboration workspace metadata
- `Odyssey/Models/BlackboardEntry.swift` — mirrored blackboard key/value record
- `Odyssey/Models/Peer.swift` — discovered LAN peer and shared agent metadata
- `Odyssey/Models/TaskItem.swift` — task board item with lifecycle, labels, assignment, result
- `Odyssey/Models/UnifiedLogEntry.swift` — normalized app/sidecar log entry

### Important Swift services

- `Odyssey/Services/SidecarManager.swift` — Bun process lifecycle, WebSocket connection, async event stream
- `Odyssey/Services/SidecarProtocol.swift` — shared wire enums/structs for commands and events
- `Odyssey/Services/AgentProvisioner.swift` — turns SwiftData configuration into `AgentConfig`
- `Odyssey/Services/WorkspaceResolver.swift` — GitHub clone destinations and workspace URL/path logic
- `Odyssey/Services/GitHubIntegration.swift` — clone/update operations
- `Odyssey/Services/GitWorkspacePreparer.swift` — prepares Git-backed workspace before first sidecar turn
- `Odyssey/Services/P2PNetworkManager.swift` — Bonjour browse/advertise and peer fetch
- `Odyssey/Services/PeerCatalogServer.swift` — local HTTP endpoint for agent sharing
- `Odyssey/Services/PeerAgentImporter.swift` — imports peer-advertised agents into local models
- `Odyssey/Services/LogAggregator.swift` — combines OSLog polling and sidecar log tailing
- `Odyssey/Services/ConfigFileManager.swift` — loads bundled skills/templates/config files
- `Odyssey/Services/ConfigSyncService.swift` — keeps app/sidecar config aligned

### Important views

- `Odyssey/Views/MainWindow/MainWindowView.swift` — `NavigationSplitView` shell with sidebar, chat, inspector, toolbar actions, and library sheet wiring
- `Odyssey/Views/MainWindow/IntentLibraryHubView.swift` — intent-first library hub (`Run`, `Build`, `Discover`) and adaptive compact/wide layouts
- `Odyssey/Views/MainWindow/SidebarView.swift` — pinned/active/recent/archived conversation organization, context menus, swipe actions
- `Odyssey/Views/MainWindow/ChatView.swift` — send flow, session bootstrap, streaming text, group chat sequencing/fan-out
- `Odyssey/Views/MainWindow/InspectorView.swift` — topic/session metadata, controls, usage counters, editor link
- `Odyssey/Views/MainWindow/NewSessionSheet.swift` — agent picker, mission, model/mode overrides, working directory picker
- `Odyssey/Views/MainWindow/PeerNetworkView.swift` — LAN peer discovery/import UI
- `Odyssey/Views/MainWindow/TaskCreationSheet.swift` and `TaskEditSheet.swift` — task board editing
- `Odyssey/Views/AgentLibrary/AgentEditorView.swift` — agent CRUD editor used from Build and install flows
- `Odyssey/Views/GroupLibrary/GroupEditorView.swift` — group CRUD editor used from Build flows
- `Odyssey/Views/Components/AgentCardView.swift` — agent launch card with working Start action
- `Odyssey/Views/Debug/DebugLogView.swift` — log viewer with filters and search

### Important sidecar modules

- `sidecar/src/ws-server.ts` — receives `session.*`, `delegate.*`, config, and task-related commands
- `sidecar/src/session-manager.ts` — session create/send/resume/fork/pause behavior and SDK stream handling
- `sidecar/src/http-server.ts` — blackboard API and health/CORS handling
- `sidecar/src/api-router.ts` — task API endpoints
- `sidecar/src/stores/blackboard-store.ts` — in-memory plus disk-backed blackboard
- `sidecar/src/stores/session-registry.ts` — per-session config/status/cost/session ID tracking
- `sidecar/src/stores/task-board-store.ts` — task persistence and atomic claim/update behavior
- `sidecar/src/tools/ask-user-tool.ts` — interactive user input tool
- `sidecar/src/tools/rich-display-tools.ts` — render/progress/action suggestion tools
- `sidecar/src/tools/task-board-tools.ts` — task board MCP-style tools
- `sidecar/src/tools/messaging-tools.ts` — peer send/broadcast/delegation tools
- `sidecar/src/tools/chat-tools.ts` — peer chat, workspace, and blackboard collaboration tools
- `sidecar/src/tools/peerbus-server.ts` — in-process MCP server exposing PeerBus tools

## Core Architecture Details

### Swift side

- `AppState` is the single global observable object for sidecar status, selections, streaming text, counters, and sheets.
- Persistence uses SwiftData models with UUID references instead of SwiftData relationships where flexibility matters.
- `AgentProvisioner` resolves the effective `AgentConfig` and working directory using this priority:
  1. Explicit override
  2. GitHub clone path
  3. Agent default working directory
  4. Ephemeral sandbox
- `GitWorkspacePreparer` ensures a GitHub-backed workspace exists before the first sidecar message.

### Sidecar side

- `SessionManager.sendMessage()` calls the Claude Agent SDK `query()` stream.
- SDK messages are translated into sidecar events such as `stream.token`, `stream.toolCall`, `stream.toolResult`, `session.result`, and `session.error`.
- Plan mode switches model behavior and appends the plan prompt from `src/prompts/plan-mode.ts`.
- Blackboard and task board data persist under `~/.odyssey/`.

### Ownership boundary

- Swift owns user-visible state and persisted conversations.
- Sidecar owns live agent execution and MCP-like tool behavior.
- If you add a feature crossing the boundary, update both transport types and both sides' handlers in the same change.

## Important User Flows

### First message in a new agent session

1. `ChatView` detects no active sidecar session.
2. `AgentProvisioner.provision()` builds `AgentConfig` and creates the `Session`.
3. Swift sends `session.create`.
4. Sidecar registers the session.
5. Swift sends `session.message`.
6. Streaming events update `AppState.streamingText[sessionId]`.

### Group chat

- Group chats are conversations with more than one `Session`.
- Each user message is sent to every session in sequence using `GroupPromptBuilder.buildMessageText`.
- After an assistant reply is saved, peer notifications may fan out using `buildPeerNotifyPrompt`.
- `GroupPeerFanOutContext` handles budget limits and deduplication.
- `@mentions` add agents to the conversation, but do not restrict the user turn to just the mentioned agent.

### Task board

1. Swift creates or edits `TaskItem`.
2. Sidecar persists task state in `~/.odyssey/taskboard/{scope}.json`.
3. Task events broadcast back to Swift and update SwiftData.
4. Agents can interact through the task board tools.

## Event/Data Flow Reference

### Standard chat turn

1. `ChatView` saves the user message into SwiftData.
2. Swift sends `session.message` through `AppState` and `SidecarManager`.
3. `WsServer` routes the command to `SessionManager.sendMessage()`.
4. `SessionManager` streams Claude SDK output.
5. Sidecar emits `stream.*` and `session.*` events.
6. `AppState.handleEvent()` updates streaming buffers and persisted state.
7. `ChatView` renders the live response.

### First message session bootstrap

1. `ChatView` sees no active sidecar session.
2. `AgentProvisioner.provision()` builds config and `Session`.
3. Swift saves the `Session` and sends `session.create`.
4. Sidecar registers the session.
5. Swift follows with `session.message`.

### Group chat specifics

- Sessions are keyed by `Session.id.uuidString` for sidecar routing.
- Each session receives a transcript delta plus the new user line.
- Assistant replies can trigger peer notifications to the other sessions.
- `GroupPeerFanOutContext` limits extra turns and deduplicates repeated notifications.

## Current Feature Baseline

The docs describe the following as implemented:

- Multi-session chat with persistent conversations
- Agent templates with skills, MCP servers, permissions, models, and working directories
- Group chat, fan-out prompts, and dynamic agent invites
- Blackboard HTTP API plus agent tools
- Task board model, sidecar store, REST API, and agent tools
- Rich display tools, ask-user inputs, plan mode, and structured logging
- GitHub-backed workspaces and pre-run clone preparation
- P2P v1 LAN discovery/import
- Chat export, attachments, streamed images/file cards/thinking
- File inspector/file tree workflows
- Launch parameters and `odyssey://` deep links
- Accessibility coverage intended for AppXray/Argus automation

## Known Gaps

Still listed as future or incomplete in the docs:

- Crash recovery / watchdog / reconnect-after-restart
- Full P2P v2 remote routing and relay flows
- Blackboard exposed as an external MCP server
- Some pool-management views as dedicated UI surfaces
- Vision-level hook engine depth beyond current streaming/tool handling

## Editing Guidance

### When changing Swift models or UI

- Keep model registration in sync with `OdysseyApp.swift`.
- Keep `AppState.handleEvent()` aligned with any new event payloads.
- Add or update accessibility identifiers when UI changes.
- Preserve the existing `NavigationSplitView` main-window structure unless the user asks for a redesign.

### When changing sidecar protocol

- Update `sidecar/src/types.ts`.
- Update `Odyssey/Services/SidecarProtocol.swift`.
- Update JSON encoding/decoding.
- Update `sidecar/src/ws-server.ts` dispatch.
- Update `AppState.handleEvent()` for new incoming events.
- Add or update tests on both sides.

### When changing agent/tool behavior

- Check whether the change belongs in Swift provisioning or sidecar execution.
- PeerBus tools live in `sidecar/src/tools/`.
- Shared tool context lives in `sidecar/src/tools/tool-context.ts`.
- Task-related transport may also require `sidecar/src/api-router.ts` and Swift task-event handling.

## Common Change Playbooks

### Add a SwiftData model

1. Create the file in `Odyssey/Models/`.
2. Register it in the model container in `OdysseyApp.swift`.
3. Regenerate the Xcode project if the file is new.

### Add a sidecar command

1. Add the type in `sidecar/src/types.ts`.
2. Add the matching Swift enum case and payload in `SidecarProtocol.swift`.
3. Encode it in Swift.
4. Handle it in `sidecar/src/ws-server.ts`.

### Add a sidecar event

1. Add the type in `sidecar/src/types.ts`.
2. Add the matching Swift event type in `SidecarProtocol.swift`.
3. Decode it in `IncomingWireMessage.toEvent()`.
4. Handle it in `AppState.handleEvent()`.

### Add a launch parameter

1. Update `Odyssey/App/LaunchIntent.swift`.
2. Update URL parsing in the same file.
3. Carry the new field through `LaunchIntent` (or add a `LaunchMode` case).
4. Handle it in `AppState.executeLaunchIntent()`.
5. Update the table in "Launching the app for tests" below so the next agent finds it.

### Launching the app for tests

Every test/scripted scenario can avoid driving the GUI by using one of these entry points. The app accepts both CLI flags (only honoured when launched from a fresh process) and `odyssey://` URLs (also work to retarget an already-running app via `open -a Odyssey.app "<url>"`).

| Goal | URL | CLI |
| --- | --- | --- |
| New freeform chat (auto-send a prompt) | `odyssey://chat?prompt=...` | `--chat --prompt "..."` |
| New chat with a named agent | `odyssey://agent/Coder?prompt=...&workdir=/path&autonomous=true` | `--agent Coder --prompt "..." --workdir /path --autonomous` |
| New chat with a named group | `odyssey://group/Dev%20Team?autonomous=true` | `--group "Dev Team" --autonomous` |
| **Open an existing conversation** | `odyssey://chat?conversation=<UUID>&prompt=...` | `--conversation <UUID> --prompt "..."` |
| **Open the conversation containing a session** | `odyssey://chat?session=<UUID>&prompt=...` | `--session <UUID> --prompt "..."` |
| Run a saved schedule | `odyssey://schedule/<UUID>?occurrence=2026-03-27T06:00:00Z` | `--schedule <UUID> --occurrence ...` |

The `?conversation` / `?session` (and matching `--conversation` / `--session`) forms are the testing affordance: they navigate to an existing thread instead of creating a new one. Combine with the `MockRuntime` `STREAM:<chars>:<rate>` magic prefix in the prompt to drive a sustained mock stream without spending Claude credits, e.g.:

```sh
open -a /path/to/Debug/Odyssey.app "odyssey://chat?conversation=$UUID&prompt=STREAM:4000:12"
```

Use `open -a` with a URL when launching a fresh DEBUG build — `WindowGroup(for: String.self)` does not auto-open a window without a document, so plain `open Odyssey.app` can leave you with a running process and zero windows. The grammar lives in `Odyssey/App/LaunchIntent.swift`; legacy `claudestudio://` and `claudpeer://` schemes still work for back-compat.

### Add a task board capability

1. Update `sidecar/src/tools/task-board-tools.ts`.
2. Update `sidecar/src/stores/task-board-store.ts`.
3. Update REST routing in `sidecar/src/api-router.ts` if needed.
4. Add matching wire/event types and Swift handling.

## Testing Expectations

### Swift tests

Run:

```bash
xcodebuild test -project Odyssey.xcodeproj -scheme Odyssey -destination 'platform=macOS'
```

Important areas already covered include:

- `AppState` event handling
- protocol encode/decode
- catalog services
- file explorer/git services
- instance config
- `GroupPromptBuilder` and fan-out behavior

### Sidecar tests

Run from `sidecar/`:

```bash
bun test
```

For live Claude SDK coverage:

```bash
ODYSSEY_E2E_LIVE=1 bun test
```

Use `sanity-tests.md` as the most precise guide for current sidecar suites. It documents unit, integration, API, and E2E groups, and notes that the E2E files boot their own sidecar subprocesses on random ports.

### UI / automation

- `TESTING.md` is the source of truth for accessibility IDs and selector conventions.
- AppXray is the inside-out DEBUG build tool.
- Argus is the outside-in macOS automation tool.
- Use the naming pattern `viewName.elementName`, with `.\(uuid)` for dynamic rows.

## Accessibility Rules

- Every interactive or semantically meaningful SwiftUI element should get an accessibility identifier.
- Icon-only controls need a human-readable accessibility label.
- Dynamic rows should suffix the item UUID.
- Do not reuse identifiers across different screens.

Key prefixes used in the repo include:

- `mainWindow.*`
- `sidebar.*`
- `libraryHub.*`
- `chat.*`
- `inspector.*`
- `newSession.*`
- `agentLibrary.*`
- `agentEditor.*`
- `peerNetwork.*`
- `taskCreation.*`
- `taskEdit.*`
- `debugLog.*`

## Build and Runtime Notes

- Xcode project is managed via `project.yml` and XcodeGen.
- Bun is resolved from common install paths or a configured override.
- The sidecar can be discovered from the app bundle, current working directory, `~/Odyssey/sidecar/`, or a configured path.
- Runtime data lives under `~/.odyssey/`.

Environment and defaults:

- `ANTHROPIC_API_KEY` — required for Claude Agent SDK work
- `ODYSSEY_WS_PORT` — default `9849`
- `ODYSSEY_HTTP_PORT` — default `9850`

## High-Signal Files

If you only open a few files, start here:

- `CLAUDE.md`
- `Odyssey/App/AppState.swift`
- `Odyssey/Services/SidecarProtocol.swift`
- `Odyssey/Services/AgentProvisioner.swift`
- `Odyssey/Views/MainWindow/ChatView.swift`
- `sidecar/src/ws-server.ts`
- `sidecar/src/session-manager.ts`
- `sidecar/src/types.ts`
- `TESTING.md`
- `SPEC.md`

## Practical Advice For Future Agents

- Prefer `CLAUDE.md` when repo docs disagree about process.
- Prefer `SPEC.md` when deciding whether a feature is already implemented.
- Prefer `TESTING.md` for selectors and test workflow details.
- Prefer `sanity-tests.md` for the current sidecar test inventory.
- Be cautious around partially implemented vision items: some are documented in `system-plan-vision.md` but not present in code.
- Before making a cross-boundary feature change, trace the full request/response flow end to end.
