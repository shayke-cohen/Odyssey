# iOS Argus E2E Test Plan — Design Spec

**Date:** 2026-04-14  
**Branch:** p2p-ios  
**Target:** OdysseyiOS on iOS 26.4 simulator (iPhone 17)  
**Approach:** Real sidecar integration (Approach B)

---

## Overview

End-to-end Argus tests for the OdysseyiOS thin-client app running on iOS 26.4 simulator. Tests cover the full user journey: initial pairing, all three main tabs (Conversations, Agents, Settings), chat interaction, and iOS 26 visual quality.

No mocks — the real Bun sidecar runs on `localhost:9849/9850` and the iOS app connects to it via `wss://` with TLS cert pinning.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Argus Test Runner                                      │
│  1. gen-test-invite.ts reads ~/.odyssey/instances/      │
│     default/ → produces base64url invite code          │
│  2. Argus allocates iPhone 17 (iOS 26.4) simulator     │
│  3. Installs + launches OdysseyiOS.app                  │
│  4. Runs pairing + connected-screen test groups        │
└─────────────────────────────────────────────────────────┘
          │                            │
          ▼                            ▼
  iOS Simulator                   Real Sidecar
  OdysseyiOS.app                  bun run start
  - TLS cert pinning              port 9849 (WSS)
  - PeerCredentialStore           port 9850 (HTTPS REST)
  - No code changes needed        ~/.odyssey/instances/default/
```

### Credential seeding

The sidecar generates a self-signed RSA-2048 TLS cert and Ed25519 keypair on first launch, stored at:

```
~/.odyssey/instances/default/tls.cert.pem
~/.odyssey/instances/default/tls.key.pem
```

The WS bearer token is stored in the Mac Keychain under service `com.odyssey.app`, account key `odyssey.wstoken.default`.

A new script `scripts/gen-test-invite.ts` (Bun) reads these, builds a valid `InvitePayload` (TTL: 10 min, `singleUse: false`), signs it with the Ed25519 private key via a Swift subprocess helper (`scripts/sign-invite-helper.swift`), and prints the base64url invite code to stdout.

The Argus test uses this code to drive the **real pairing UI** — no bypass, no keychain injection. This tests the complete user-facing pairing path.

### Prerequisites

Before running tests, the following must be true:

1. Sidecar is running: `cd sidecar && bun run start`
2. Mac Odyssey app has been launched at least once (creates identity/TLS cert)
3. OdysseyiOS.app is installed in the booted simulator (built via `xcodebuild`)
4. iPhone 17 simulator is booted (`xcrun simctl boot <UDID>`)

The test runner checks these preconditions and prints a clear error if any are missing.

---

## Test Groups

### Group 1 — Pairing (no prior credentials)

Tests the first-launch experience. State reset = uninstall + reinstall the app via `simctl uninstall` / `simctl install` before each pairing test; this clears the app's Keychain items on simulator.

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| P-1 | Fresh launch shows pairing screen | Launch app | `pairing.inviteCodeField` visible, `pairing.pairButton` disabled |
| P-2 | Pair button disabled with empty field | Launch, do nothing | `pairing.pairButton` disabled |
| P-3 | Invalid code shows error | Enter `notavalidcode`, tap Pair | `pairing.errorLabel` visible with error text |
| P-4 | Valid invite → navigates to tab bar | Enter real invite code, tap Pair | `tab.conversations` tab bar appears |
| P-5 | Deep link auto-pairs | Open `odyssey://connect?invite=<code>` URL | Pairing succeeds, navigates to tab bar |

### Group 2 — Conversations Tab

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| C-1 | Conversation list loads | Navigate to Conversations tab | `conversationList.list` visible (or `conversationList.emptyState`) |
| C-2 | Empty state when no conversations | Run before Mac app syncs any convos (fresh sidecar start) | `conversationList.emptyState` shown |
| C-3 | Search filters results | `conversation-seed.ts` posts one convo; search its title | Row appears; search for gibberish → empty |
| C-4 | Refresh button reloads | Tap `conversationList.refreshButton` | List reloads (spinner then content) |
| C-5 | Pull-to-refresh | Pull down on list | List refreshes |
| C-6 | Row tap → chat view | Tap `conversationList.row.*` | `chat.messageList` appears, nav title = topic |

### Group 3 — Chat View

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| CH-1 | Message history loads | Open conversation with messages | `chat.message.*` cells visible |
| CH-2 | Send button disabled when empty | Open chat, clear input | `chat.sendButton` disabled |
| CH-3 | Send button enabled with text | Type into `chat.inputField` | `chat.sendButton` enabled |
| CH-4 | Send message | Type "hello", tap send | Input clears, message appears |
| CH-5 | Streaming indicator | Send message to active agent | `chat.streamingBubble` appears while streaming |

### Group 4 — Agents Tab

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| A-1 | Agent list loads | Navigate to Agents tab | `agentList.list` or `agentList.emptyState` visible |
| A-2 | Connection badge is green | While connected | `connectionStatus.badge` has green indicator |
| A-3 | Refresh loads agents | Tap `agentList.refreshButton` | `agentList.loadingIndicator` → list |
| A-4 | Tap agent → New Conversation sheet | Tap `agentList.startButton.*` | `newConversation.messageField` visible |
| A-5 | Start conversation | Fill message, tap `newConversation.startButton` | Sheet dismisses, conversation added |
| A-6 | Cancel sheet | Tap `newConversation.cancelButton` | Sheet dismisses, no new conversation |

### Group 5 — Settings Tab

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| S-1 | Paired Mac in list | After pairing | `settings.pairedMacRow.*` visible with Mac display name |
| S-2 | LAN hint shown | Check row subtitle | LAN address displayed |
| S-3 | Unpair removes Mac | Tap `settings.unpairButton.*` | Row disappears |
| S-4 | Unpair → disconnected | Tap unpair, check connection section | `settings.reconnectButton` or disconnected status |
| S-5 | Add Mac → pairing sheet | Tap `settings.addMacButton` | `pairing.inviteCodeField` visible in sheet |
| S-6 | Version shown | Check About section | `settings.version` has a non-empty value |

### Group 6 — iOS 26 Visual Quality

Screenshot-based visual checks. Pass/fail is human-reviewed on first run; screenshots are saved to `docs/screenshots/ios26/`.

| ID | Scenario | Check |
|----|----------|-------|
| V-1 | Tab bar (Conversations) | Liquid glass tab bar visible |
| V-2 | Navigation bar | iOS 26 large title style in Conversations |
| V-3 | Chat view | Bubble layout, send button placement |
| V-4 | Settings form | iOS 26 grouped form appearance |
| V-5 | Dark mode — pairing | Correct background/text colors |
| V-6 | Dark mode — conversations | List cells readable in dark mode |
| V-7 | Dark mode — chat | Bubbles use correct dark colors |
| V-8 | Dark mode — settings | Form sections correct in dark |

---

## File Layout

```
scripts/
  gen-test-invite.ts          # Bun: reads sidecar identity → prints invite code
  sign-invite-helper.swift    # Swift subprocess: Ed25519 sign, called by gen-test-invite.ts

sidecar/test/
  argus-ios.ts                # Main Argus test file (all 6 groups)
  fixtures/
    conversation-seed.ts      # Utility to POST a test conversation to the sidecar

docs/screenshots/ios26/       # Visual check output (gitignored except golden copies)
```

---

## Accessibility Identifiers Referenced

All identifiers already exist in the app. No new ones needed.

```
pairing.inviteCodeField      pairing.pairButton          pairing.errorLabel
pairing.cancelButton         tab.conversations            tab.agents
tab.settings                 conversationList.list        conversationList.emptyState
conversationList.row.*       conversationList.search      conversationList.refreshButton
conversationList.newButton   chat.messageList             chat.message.*
chat.inputField              chat.sendButton              chat.streamingBubble
chat.errorLabel              agentList.list               agentList.emptyState
agentList.row.*              agentList.startButton.*      agentList.loadingIndicator
agentList.refreshButton      connectionStatus.badge       newConversation.messageField
newConversation.startButton  newConversation.cancelButton settings.pairedMacRow.*
settings.unpairButton.*      settings.addMacButton        settings.version
settings.reconnectButton     settings.noPairedMacs
```

---

## Out of Scope

- Matrix/federation flows (Phase 6) — separate test plan
- Group chat fan-out — macOS-only
- AppXray inspector overlay
- Performance/load testing
