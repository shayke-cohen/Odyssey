---
name: odyssey-testing
description: Testing workflow for Odyssey — when to use AppXray vs sidecar API vs XCTest, how to run feedback checks, and how to diagnose failures
---

# Odyssey Testing Workflow

## When to Use Which Tool

| What you changed | How to verify |
| --- | --- |
| Swift / SwiftUI UI | `make build-check` + AppXray inspect |
| Sidecar TypeScript | `make sidecar-smoke` (mock) |
| Any change end-to-end | `make feedback` (~20s) |
| Full agent behavior | `make feedback-full` (real Claude, ~50s) |
| Specific UI element | AppXray `inspect` + `assert` |
| AppState property | AppXray `setState` + `inspect` |
| Sidecar REST route | `curl localhost:9850/api/v1/...` |

**Never** claim a task is done without running at least `make build-check` for Swift changes or `make sidecar-smoke` for sidecar changes.

## Fast Feedback Commands

```sh
make build-check      # xcodebuild compile only — ~15s
make sidecar-smoke    # mock provider smoke test — ~2s (requires sidecar running)
make feedback         # build-check + sidecar-smoke — ~20s
make feedback-full    # build-check + real Claude smoke — ~50s
```

`make sidecar-smoke` uses `provider: "mock"` — no Claude API calls, no cost, completes in under 2 seconds. Use `make feedback-full` only when verifying actual agent behavior.

## AppXray Workflow (macOS App)

AppXray connects to the running DEBUG app on port 19480. The app must already be running.

```
1. mcp__appxray__session  action:"discover"   → find Odyssey
2. mcp__appxray__session  action:"connect"
3. mcp__appxray__inspect                      → screenshot + a11y tree
4. mcp__appxray__act      selector/action     → interact
5. mcp__appxray__assert   selector/condition  → verify
```

Selectors:
- `@testId("chat.sendButton")` — matches `.accessibilityIdentifier()` / `.xrayId()`
- `@label("Send message")` — matches `.accessibilityLabel()`
- `@text("Cancel")` — matches visible text

## Injecting State Without a Live Sidecar

These AppXray setters are registered in `OdysseyApp.swift` and work even when the sidecar is disconnected:

| Key | Type | Effect |
| --- | --- | --- |
| `showAddAgentsToChatSheet` | Bool | Opens AddAgentsToChatSheet |
| `sidecarStatusOverrideForTesting` | String (`"connected"`, `"connecting"`, `"disconnected"`) | Overrides sidecar status pill |

Example:

```
mcp__appxray__act  action:"setState"  key:"showAddAgentsToChatSheet"  value:true
```

## Reading AppState Properties via AppXray

After any action, read live AppState values:

```
mcp__appxray__inspect  → look for appState.* in the properties section
```

Readable properties include `sidecarStatus`, `isInspectorVisible`, `showAddAgentsToChatSheet`, and all `@Published` vars on `AppState`.

## YAML Regression Specs

Spec files live in `tests/appxray/`. Run them by connecting AppXray to the app and executing steps manually or via batch.

| Spec | What it covers |
| --- | --- |
| `add-agents-to-chat.yaml` | AddAgentsToChatSheet — open via setState, verify buttons |
| `agent-groups.yaml` | Sidebar Groups section — rows, context menu, add button |
| `workspace-menu.yaml` | Workspace toolbar menu — Schedules, Agent Comms, Debug Log |
| `delegation-ui.yaml` | Auto-Answer badge and delegation mode picker |
| `thread-creation-popover.yaml` | New thread popover |
| `schedule-smoke.yaml` | Schedule library smoke |

## Sidecar Observability API

Use these endpoints to debug after a failed smoke or to inspect turn history:

```sh
# Global state
curl localhost:9850/api/v1/debug/state

# Last N log entries (filter by level or category)
curl "localhost:9850/api/v1/debug/logs?tail=20"
curl "localhost:9850/api/v1/debug/logs?tail=20&level=error"
curl "localhost:9850/api/v1/debug/logs?tail=20&category=session"

# Per-session turn history
curl localhost:9850/api/v1/sessions/{id}/turns

# Per-session SSE event history (last 100 events)
curl localhost:9850/api/v1/sessions/{id}/events/history
```

## Mock Provider

Sessions created with `provider: "mock"` skip Claude entirely and echo the input immediately. The mock runtime is registered in `sidecar/src/session-manager.ts`.

Use it in agent config:

```json
{ "provider": "mock", "model": "claude-haiku-4-5-20251001", ... }
```

The quick-smoke test (`sidecar/test/feedback/quick-smoke.ts`) uses mock by default. Set `USE_REAL_CLAUDE=1` to switch to real Claude.

## Common Failure Patterns

**Build fails — type error in Swift:**
- Run `make build-check` for the full error output (last 30 lines printed on failure)
- Check Swift 6 concurrency: UI mutations must be `@MainActor` or via `DispatchQueue.main.async`

**`make sidecar-smoke` fails — connection refused:**
- Start the sidecar: `cd sidecar && bun run src/index.ts`
- Confirm it's healthy: `curl localhost:9850/api/v1/debug/state`

**`make sidecar-smoke` fails — turn did not complete:**
- Check logs: `curl "localhost:9850/api/v1/debug/logs?tail=20&level=error"`
- Check turns: `curl localhost:9850/api/v1/sessions/{id}/turns`

**AppXray — element not found:**
- Run `mcp__appxray__inspect` and check the returned accessibility tree
- Confirm the element has `.xrayId()` or `.accessibilityIdentifier()` set
- Check the prefix map in `CLAUDE.md` for the correct identifier format

**AppXray — setState has no effect:**
- Confirm the setter is registered in `OdysseyApp.swift` `registerObservableObject` call
- Only `@Published` properties on `AppState` can be set this way

## XCTest (Unit / Integration)

XCTest lives in `OdysseyTests/`. Run via Xcode or:

```sh
xcodebuild test -project Odyssey.xcodeproj -scheme OdysseyTests -destination 'platform=macOS'
```

Key test files:
- `GroupPromptBuilderTests.swift` — group chat transcript, peer prompts, fan-out context
- Sidecar unit tests: `cd sidecar && bun test`
